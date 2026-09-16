const std = @import("std");
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

    const args = spl.cli.Args.parse(init.args) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return 2;
    };

    return mainArgs(io, gpa, args);
}

fn mainArgs(io: std.Io, gpa: std.mem.Allocator, args: spl.cli.Args) u8 {
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);

    if (args.help) {
        stdout_writer.interface.writeAll(spl.cli.help_msg) catch return 1;
        stdout_writer.flush() catch return 1;
        return 0;
    }

    const source: spl.frontend.Source = .{ .text = readFile(io, gpa, args.source_path) catch |err| {
        std.log.err("failed to read source file: {s}", .{@errorName(err)});
        return 1;
    } };
    defer gpa.free(source.text);

    var lexer = spl.frontend.Lexer.init(source.text);
    var tokens = lexer.run(gpa) catch |err| {
        std.log.err("failed to tokenize: {s}", .{@errorName(err)});
        return 1;
    };
    defer tokens.deinit(gpa);

    if (args.tokens_dump_path) |dump_path| {
        dumpTokens(io, source, tokens, dump_path) catch |err|
            std.log.err("failed to dump tokens: {s}", .{@errorName(err)});
    }

    if (args.last_stage == .lexer) {
        const error_occured = std.mem.findAny(spl.frontend.lex.Token.Kind, tokens.items(.kind), &.{
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
        }) != null;

        if (error_occured) {
            std.log.err("tokenizing error not reported due to stage limit", .{});
            return 1;
        }

        return 0;
    }

    var error_bundle: spl.frontend.ErrorBundle = .empty;
    defer error_bundle.deinit(gpa);

    var parser = spl.frontend.Parser.init(gpa, source, tokens, &error_bundle);
    var ast = parser.parse() catch |err| {
        std.log.err("failed to parse: {s}", .{@errorName(err)});
        return 1;
    };
    defer ast.deinit(gpa);

    parser.deinit();

    if (args.ast_dump_path) |dump_path| {
        dumpAst(io, source, tokens, ast, dump_path) catch |err|
            std.log.err("failed to dump AST: {s}", .{@errorName(err)});
    }

    if (args.last_stage == .parser) {
        if (error_bundle.nonEmpty()) {
            error_bundle.sort();
            error_bundle.renderToStderr(io, source.text, null) catch {};
            return 1;
        }
        return 0;
    }

    var sema = spl.frontend.Sema.init(gpa, source, tokens, ast, &error_bundle);
    sema.run() catch |err| {
        std.log.err("failed to run semantic analysis: {s}", .{@errorName(err)});
        return 1;
    };
    sema.deinit();

    if (error_bundle.nonEmpty()) {
        error_bundle.sort();
        error_bundle.renderToStderr(io, source.text, null) catch {};
        return 1;
    }

    const llvm_output_path, const should_free_path = if (args.emit_llvm)
        .{ args.output_path, false }
    else
        .{ std.fmt.allocPrintSentinel(gpa, "{s}.bc", .{args.output_path}, 0) catch {
            std.log.err("failed to allocate temporary path", .{});
            return 1;
        }, true };

    defer if (should_free_path) gpa.free(llvm_output_path);

    var codegen = spl.Codegen.init(gpa, source, tokens, ast);
    codegen.run(llvm_output_path, .{ .emit_llvm = args.emit_llvm }) catch |err| {
        std.log.err("failed to generate code: {s}", .{@errorName(err)});
        return 1;
    };
    codegen.deinit();

    if (args.emit_llvm) {
        return 0;
    }

    const clang_argv: []const []const u8 = &.{ "clang", llvm_output_path, "-o", args.output_path };
    const res = std.process.run(gpa, io, .{ .argv = clang_argv }) catch |err| {
        std.log.err("failed to run clang: {s}", .{@errorName(err)});
        return 1;
    };
    gpa.free(res.stdout);
    gpa.free(res.stderr);

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

fn dumpTokens(
    io: std.Io,
    source: spl.frontend.Source,
    tokens: spl.frontend.lex.TokenList,
    path: []const u8,
) !void {
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
            .assign => "ASSIGN",
            .plus => "PLUS",
            .minus => "MINUS",
            .asterisk => "MULT",
            .slash => "DIV",
            .lparen => "LPAREN",
            .rparen => "RPAREN",
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
            .err_ident_too_long,
            => "ERROR",
        };

        const error_msg = switch (token.kind) {
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
            .err_ident_too_long,
            => token.kind.toString(),
            else => null,
        };

        const loc = source.locationFromOffset(token.offset);

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
    source: spl.frontend.Source,
    tokens: spl.frontend.lex.TokenList,
    ast: spl.frontend.Ast,
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
    source: spl.frontend.Source,
    tokens: spl.frontend.lex.TokenList,
    ast: spl.frontend.Ast,
    node_index: spl.frontend.Ast.Node.Index,
) !void {
    const node = ast.nodes.get(@intFromEnum(node_index));

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
            try jws.write(source.tokenLiteral(tokens.get(node.token + 1)));

            try jws.objectField("value");
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .name_ref => {
            try jws.objectField("name");
            try jws.write(source.tokenLiteral(tokens.get(node.token)));
        },
        .number => {
            try jws.objectField("value");
            try jws.beginWriteRaw();
            try jws.writer.writeAll(source.tokenLiteral(tokens.get(node.token)));
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
