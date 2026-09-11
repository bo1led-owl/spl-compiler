const std = @import("std");

const Args = @import("driver/Args.zig");
const spl = @import("spl");

var stdout_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;
var dump_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

pub fn main(init: std.process.Init.Minimal) u8 {
    const gpa = std.heap.smp_allocator;

    var io_impl = std.Io.Threaded.init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer io_impl.deinit();
    const io = io_impl.io();

    const args = Args.parse(init.args) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return 2;
    };

    const source = readFile(io, gpa, args.path) catch |err| {
        std.log.err("failed to read source file: {s}", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(source);

    var lexer = spl.lex.Lexer.init(source);
    var tokens = lexer.run(gpa) catch |err| {
        std.log.err("failed to tokenize: {s}", .{@errorName(err)});
        return 1;
    };
    defer tokens.deinit(gpa);

    if (args.tokens_dump_path) |dump_path| {
        dumpTokens(io, source, tokens, dump_path) catch |err|
            std.log.err("failed to dump tokens: {s}", .{@errorName(err)});
    }

    var error_bundle: spl.ErrorBundle = .init(gpa);
    defer error_bundle.deinit();

    var parser = spl.Parser.init(gpa, source, tokens, &error_bundle);
    var ast = parser.parse() catch |err| {
        std.log.err("failed to parse: {s}", .{@errorName(err)});
        return 1;
    };
    defer ast.deinit(gpa);

    if (args.ast_dump_path) |dump_path| {
        dumpAst(io, source, tokens, ast, dump_path) catch |err|
            std.log.err("failed to dump AST: {s}", .{@errorName(err)});
    }

    if (error_bundle.nonEmpty()) {
        error_bundle.renderToStderr(io, null, source) catch {};
    }

    return 0;
}

fn readFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const size = try file.length(io);

    if (size > std.math.maxInt(u32)) {
        return error.FileTooLarge;
    }

    const result: []u8 = try gpa.alloc(u8, size);
    errdefer gpa.free(result);

    var result_writer = std.Io.Writer.fixed(result);

    var reader = file.reader(io, &.{});
    try reader.interface.streamExact(&result_writer, size);

    return result;
}

fn dumpTokens(io: std.Io, source: []const u8, tokens: spl.lex.TokenList, path: []const u8) !void {
    const dump_file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer dump_file.close(io);

    var writer = dump_file.writer(io, &dump_buffer);
    var jws = std.json.Stringify{ .writer = &writer.interface, .options = .{ .whitespace = .indent_2 } };

    try jws.beginArray();

    for (0..tokens.len) |i| {
        const token = tokens.get(i);

        const kind_name = switch (token.kind) {
            .eof => "EOF",
            .number => "INT",
            .ident => "IDENT",
            .kw_val => "VAL",
            .kw_var => "VAR",
            .kw_return => "RETURN",
            .semi => "SEMI",
            .assign => "EQ",
            .plus => "PLUS",
            .minus => "MINUS",
            .asterisk => "MULT",
            .slash => "DIV",
            .lparen => "LPAREN",
            .rparen => "RPAREN",
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
            => "ERROR",
        };

        const error_msg = switch (token.kind) {
            .err_invalid_character => "invalid character",
            .err_number_has_leading_zero => "number has leading zero",
            .err_unterminated_multiline_comment => "unterminated multiline comment",
            else => null,
        };

        const loc = spl.lex.locationFromOffset(source, token.offset);

        try jws.beginObject();

        try jws.objectField("kind");
        try jws.write(kind_name);

        if (error_msg) |msg| {
            try jws.objectField("msg");
            try jws.write(msg);
        }

        try jws.objectField("line");
        try jws.write(loc.line);

        try jws.objectField("column");
        try jws.write(loc.column);

        try jws.endObject();
    }

    try jws.endArray();
    try writer.flush();
}

fn dumpAst(
    io: std.Io,
    source: []const u8,
    tokens: spl.lex.TokenList,
    ast: spl.Ast,
    path: []const u8,
) !void {
    const dump_file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer dump_file.close(io);

    var writer = dump_file.writer(io, &dump_buffer);
    var jws = std.json.Stringify{ .writer = &writer.interface, .options = .{ .whitespace = .indent_2 } };
    try dumpAstNode(&jws, source, tokens, ast, .root);
    try writer.flush();
}

fn dumpAstNode(
    jws: *std.json.Stringify,
    source: []const u8,
    tokens: spl.lex.TokenList,
    ast: spl.Ast,
    node_idx: spl.Ast.Node.Index,
) !void {
    const node = ast.nodes.get(@intFromEnum(node_idx));

    try jws.beginObject();

    try jws.objectField("kind");
    try jws.write(switch (node.kind) {
        .root => "Program",
        .var_decl => "Declare",
        .name_ref => "Ident",
        .number => "IntLiteral",
        .@"return" => "Return",
        .unary => "Unary",
        .binary => "BinOp",
        .assign => "Assign",
    });

    switch (node.kind) {
        .root => {
            const body = ast.extractExtras(node.data.extra_range);

            try jws.objectField("body");
            try jws.beginArray();

            for (body) |i| {
                try dumpAstNode(jws, source, tokens, ast, @enumFromInt(i));
            }

            try jws.endArray();
        },
        .var_decl => {
            try jws.objectField("mut");
            try jws.write(tokens.items(.kind)[node.token] == .kw_var);

            try jws.objectField("name");
            try jws.write(spl.lex.tokenLiteral(source, tokens.get(node.token + 1)));

            try jws.objectField("value");
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .name_ref => {
            try jws.objectField("name");
            try jws.write(spl.lex.tokenLiteral(source, tokens.get(node.token)));
        },
        .number => {
            try jws.objectField("value");
            try jws.beginWriteRaw();
            try jws.writer.writeAll(spl.lex.tokenLiteral(source, tokens.get(node.token)));
            jws.endWriteRaw();
        },
        .@"return" => {
            try jws.objectField("value");
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .unary => {
            try jws.objectField("op");
            try jws.write(tokens.items(.kind)[node.token]);

            try jws.objectField("operand");
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .binary => {
            try jws.objectField("op");
            try jws.write(tokens.items(.kind)[node.token]);

            try jws.objectField("lhs");
            try dumpAstNode(jws, source, tokens, ast, node.data.node_node.@"0");

            try jws.objectField("rhs");
            try dumpAstNode(jws, source, tokens, ast, node.data.node_node.@"1");
        },
        .assign => {
            try jws.objectField("dest");
            try dumpAstNode(jws, source, tokens, ast, node.data.node_node.@"0");
            try jws.objectField("src");
            try dumpAstNode(jws, source, tokens, ast, node.data.node_node.@"1");
        },
    }

    try jws.endObject();
}
