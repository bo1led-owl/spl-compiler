const std = @import("std");
const builtin = @import("builtin");
const frontend = @import("frontend");
const cli = @import("cli.zig");

var dump_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

const use_safe_allocator = builtin.mode == .debug or builtin.mode == .safe;
var safe_allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});

pub fn main(init: std.process.Init.Minimal) u8 {
    const gpa = if (use_safe_allocator) safe_allocator.allocator() else std.heap.smp_allocator;
    defer if (use_safe_allocator) {
        _ = safe_allocator.deinit();
    };

    var io_impl = std.Io.Threaded.init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer io_impl.deinit();

    const io = io_impl.io();

    const args = cli.Args.parse(init.args) catch |err| {
        std.log.err("failed to parse arguments: {s}", .{@errorName(err)});
        return 2;
    };

    switch (args) {
        .help => {
            std.Io.File.stdout().writeStreamingAll(io, cli.help_msg) catch return 1;
            return 0;
        },
        .full => |full_args| return mainArgs(io, gpa, full_args),
    }
}

fn printElapsed(comptime title: []const u8, from: std.Io.Timestamp, to: std.Io.Timestamp) void {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    const duration = from.durationTo(to);
    duration.format(&writer) catch return;

    std.log.info(title ++ "\t{s}", .{writer.buffered()});
}

fn mainArgs(io: std.Io, gpa: std.mem.Allocator, args: cli.Args.Full) u8 {
    const clock: std.Io.Clock = .real;
    const main_start_timestamp = clock.now(io);
    defer if (args.timings) printElapsed("total", main_start_timestamp, clock.now(io));

    var start_time: std.Io.Timestamp = undefined;
    var end_time: std.Io.Timestamp = undefined;

    const source_text = readFile(io, gpa, args.source_path, std.math.maxInt(u32)) catch |err| {
        std.log.err("failed to read source file: {s}", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(source_text);

    // lexing

    var lexer = frontend.Lexer.init(source_text);

    start_time = clock.now(io);
    var tokens = tokens: {
        var token_list = lexer.run(gpa) catch |err| {
            std.log.err("failed to tokenize: {s}", .{@errorName(err)});
            return 1;
        };
        break :tokens token_list.toOwnedSlice();
    };
    defer tokens.deinit(gpa);
    end_time = clock.now(io);

    if (args.timings) printElapsed("lexing", start_time, end_time);

    const source: frontend.Source = .{
        .filename = args.source_path,
        .text = source_text,
    };

    if (args.tokens_dump_path) |dump_path| {
        dumpTokensIntoFile(io, dump_path, source, tokens) catch |err|
            std.log.err("failed to dump tokens: {s}", .{@errorName(err)});
    }

    if (args.last_stage == .lexer) {
        const error_occured = std.mem.findAny(
            frontend.lex.Token.Kind,
            tokens.items(.kind),
            frontend.lex.Token.Kind.errors,
        ) != null;

        if (error_occured) {
            std.log.err("tokenizing error not reported due to stage limit", .{});
            return 1;
        }

        return 0;
    }

    // parsing

    var error_bundle: frontend.ErrorBundle = .init(gpa);
    defer error_bundle.deinit();

    var parser = frontend.Parser.init(gpa, source, tokens, &error_bundle);
    defer parser.deinit();

    start_time = clock.now(io);
    var ast = parser.run() catch |err| {
        std.log.err("failed to parse: {s}", .{@errorName(err)});
        return 1;
    };
    defer ast.deinit(gpa);
    end_time = clock.now(io);

    if (args.timings) printElapsed("parsing", start_time, end_time);

    if (args.ast_dump_path) |dump_path| {
        dumpAstIntoFile(io, dump_path, source, tokens, ast) catch |err|
            std.log.err("failed to dump AST: {s}", .{@errorName(err)});
    }

    if (args.last_stage == .parser) {
        if (error_bundle.nonEmpty()) {
            const stderr = io.lockStderr(&dump_buffer, null) catch
                // because nobody can cancel this
                unreachable;
            defer io.unlockStderr();

            error_bundle.renderToTerminal(source, stderr.terminal()) catch {};
            return 1;
        }
        return 0;
    }

    // sema

    var sema = frontend.Sema.init(gpa, source, tokens, ast, &error_bundle);
    defer sema.deinit();

    start_time = clock.now(io);
    sema.run() catch |err| {
        std.log.err("failed to run semantic analysis: {s}", .{@errorName(err)});
        return 1;
    };
    end_time = clock.now(io);

    if (args.timings) printElapsed("sema", start_time, end_time);

    if (error_bundle.nonEmpty()) {
        const stderr = io.lockStderr(&dump_buffer, null) catch unreachable;
        defer io.unlockStderr();

        error_bundle.renderToTerminal(source, stderr.terminal()) catch {};
        return 1;
    }

    if (args.last_stage == .sema) {
        return 0;
    }

    // codegen

    const llvm_output_path = if (args.emit_llvm)
        args.output_path
    else
        gpa.printSentinel("{s}.o", .{args.output_path}, 0) catch {
            std.log.err("failed to allocate temporary path", .{});
            return 1;
        };

    defer if (!args.emit_llvm) gpa.free(llvm_output_path);

    var codegen = frontend.Codegen.init(gpa, source, tokens, ast);
    defer codegen.deinit();

    start_time = clock.now(io);
    codegen.run(llvm_output_path, .{ .emit_llvm = args.emit_llvm }) catch |err| {
        std.log.err("failed to generate code: {s}", .{@errorName(err)});
        return 1;
    };
    end_time = clock.now(io);

    if (args.timings) printElapsed("codegen", start_time, end_time);

    if (args.emit_llvm) {
        return 0;
    }

    // linking

    const clang_argv: []const []const u8 = &.{ "clang", llvm_output_path, "libruntime/spl_runtime.c", "-o", args.output_path };

    start_time = clock.now(io);
    const res = std.process.run(gpa, io, .{ .argv = clang_argv }) catch |err| {
        std.log.err("failed to run clang: {s}", .{@errorName(err)});
        return 1;
    };
    end_time = clock.now(io);

    if (args.timings) printElapsed("linking", start_time, end_time);

    gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    if (res.term.exited != 0) {
        std.log.err("clang failed with exit code {d}, stderr:\n{s}", .{ res.term.exited, res.stderr });
        return 1;
    }

    if (!args.preserve_temp) {
        std.Io.Dir.cwd().deleteFile(io, llvm_output_path) catch |err| {
            std.log.err("failed to delete temporary file: {s}", .{@errorName(err)});
            return 1;
        };
    }

    return 0;
}

fn readFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8, max_size: u32) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false });
    defer file.close(io);

    const size = try file.length(io);
    if (size > max_size) {
        return error.FileTooLarge;
    }

    const result: []u8 = try gpa.alloc(u8, size);
    errdefer gpa.free(result);

    var result_writer = std.Io.Writer.fixed(result);

    var reader = file.reader(io, &.{});
    reader.interface.streamExact(&result_writer, size) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        error.WriteFailed => unreachable,
        error.EndOfStream => unreachable,
    };

    return result;
}

fn dumpTokensIntoFile(
    io: std.Io,
    dump_path: []const u8,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
) !void {
    const dump_file = try std.Io.Dir.cwd().createFile(io, dump_path, .{});
    defer dump_file.close(io);

    var dump_writer = dump_file.writer(io, &dump_buffer);
    dumpTokens(&dump_writer.interface, source, tokens) catch |err| {
        std.debug.assert(err == std.Io.Writer.Error.WriteFailed);
        return dump_writer.err.?;
    };
    try dump_writer.flush();
}

fn dumpTokens(
    writer: *std.Io.Writer,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
) std.Io.Writer.Error!void {
    var jws = std.json.Stringify{ .writer = writer, .options = .{ .whitespace = .indent_2 } };

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
            .kw_if => "IF",
            .kw_else => "ELSE",
            .kw_while => "WHILE",
            .kw_break => "BREAK",
            .kw_continue => "CONTINUE",
            .kw_true => "TRUE",
            .kw_false => "FALSE",
            .kw_def => "DEF",
            .kw_extern => "EXTERN",
            .comma => "COMMA",
            .semi => "SEMI",
            .assign => "ASSIGN",
            .plus => "PLUS",
            .minus => "MINUS",
            .asterisk => "MULT",
            .slash => "DIV",
            .bang => "NOT",
            .logical_and => "AND",
            .logical_or => "OR",
            .eq => "EQ",
            .ne => "NE",
            .lt => "LT",
            .gt => "GT",
            .le => "LE",
            .ge => "GE",
            .lparen => "LPAREN",
            .rparen => "RPAREN",
            .lbrace => "LBRACE",
            .rbrace => "RBRACE",
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
            => "ERROR",
        };

        const error_msg = switch (token.kind) {
            .err_invalid_character,
            .err_number_has_leading_zero,
            .err_unterminated_multiline_comment,
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

fn dumpAstIntoFile(
    io: std.Io,
    dump_path: []const u8,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
    ast: frontend.Ast,
) !void {
    const dump_file = try std.Io.Dir.cwd().createFile(io, dump_path, .{});
    defer dump_file.close(io);

    var dump_writer = dump_file.writer(io, &dump_buffer);
    dumpAst(&dump_writer.interface, source, tokens, ast) catch |err| {
        std.debug.assert(err == std.Io.Writer.Error.WriteFailed);
        return dump_writer.err.?;
    };
    try dump_writer.flush();
}

fn dumpAst(
    writer: *std.Io.Writer,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
    ast: frontend.Ast,
) std.Io.Writer.Error!void {
    var jws = std.json.Stringify{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
    try dumpAstNode(&jws, source, tokens, ast, .root);
}

fn dumpFakeIdent(
    jws: *std.json.Stringify,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
    token_index: frontend.lex.Token.Index,
) !void {
    const name_token = tokens.get(token_index);
    try jws.beginObject();

    try jws.objectField("kind");
    try jws.write("Ident");
    try jws.objectField("name");
    try jws.write(source.tokenLiteral(name_token));

    try jws.objectField("elems");
    try jws.beginArray();
    try jws.endArray();

    const name_loc = source.locationFromOffset(name_token.offset);
    try jws.objectField("line");
    try jws.write(name_loc.line);
    try jws.objectField("column");
    try jws.write(name_loc.column);

    try jws.endObject();
}

fn dumpAstNode(
    jws: *std.json.Stringify,
    source: frontend.Source,
    tokens: frontend.lex.TokenList.Slice,
    ast: frontend.Ast,
    node_index: frontend.Ast.Node.Index,
) !void {
    const node = ast.nodes.get(node_index.toU32());

    try jws.beginObject();

    try jws.objectField("kind");
    try jws.write(switch (node.kind) {
        .root => "Program",
        .var_decl => "Declare",
        .name_ref => "Ident",
        .bool_literal => "BoolLiteral",
        .number => "IntLiteral",
        .call => "Call",
        .fn_decl => "FuncDecl",
        .fn_proto => if (tokens.items(.kind)[node.token] == .kw_extern) "ExternDecl" else "FuncDecl",
        .@"return" => "Return",
        .unary => "Unary",
        .binary => "BinOp",
        .assign => "Assign",
        .recovery => "Error",
        .if_simple, .if_full => "If",
        .@"while" => "While",
        .@"continue" => "Continue",
        .@"break" => "Break",
        .block => "Block",
    });

    const loc = source.locationFromOffset(tokens.items(.offset)[node.token]);
    try jws.objectField("line");
    try jws.write(loc.line);
    try jws.objectField("column");
    try jws.write(loc.column);

    // everything except `kind` and `elems`
    switch (node.kind) {
        .root => {},
        .recovery => {},
        .@"return" => {},
        .assign => {},
        .block => {},
        .@"while" => {},
        .@"continue", .@"break" => {},
        .call => {},
        .fn_decl, .fn_proto => {},
        .if_simple, .if_full => {},
        .var_decl => {
            try jws.objectField("mut");
            try jws.write(tokens.items(.kind)[node.token] == .kw_var);
        },
        .name_ref => {
            try jws.objectField("name");
            try jws.write(source.tokenLiteral(tokens.get(node.token)));
        },
        .bool_literal => {
            try jws.objectField("value");
            try jws.write(tokens.items(.kind)[node.token] == .kw_true);
        },
        .number => {
            try jws.objectField("value");
            try jws.beginWriteRaw();
            try jws.writer.writeAll(source.tokenLiteral(tokens.get(node.token)));
            jws.endWriteRaw();
        },
        .unary => {
            try jws.objectField("op");
            try jws.write(tokens.items(.kind)[node.token]);
        },
        .binary => {
            try jws.objectField("op");
            try jws.write(tokens.items(.kind)[node.token]);
        },
    }

    try jws.objectField("elems");
    try jws.beginArray();

    switch (node.kind) {
        .recovery => {},
        .name_ref => {},
        .bool_literal => {},
        .number => {},
        .@"continue" => {},
        .@"break" => {},
        .root => {
            const body = ast.extractExtras(node.data.extra_range);
            for (body) |i| {
                try dumpAstNode(jws, source, tokens, ast, @fromBackingInt(i));
            }
        },
        .call => {
            const info = frontend.Ast.info.call(ast, node_index);

            try dumpAstNode(jws, source, tokens, ast, info.callee);
            for (info.args) |arg| {
                try dumpAstNode(jws, source, tokens, ast, arg);
            }
        },
        .fn_proto => {
            const proto_info = frontend.Ast.info.fnProto(ast, tokens, node_index);

            try dumpFakeIdent(jws, source, tokens, proto_info.name_token);
            for (proto_info.params) |param| {
                try dumpFakeIdent(jws, source, tokens, param);
            }
        },
        .fn_decl => {
            const proto, const body = node.data.node_and_node;
            const proto_info = frontend.Ast.info.fnProto(ast, tokens, proto);

            try dumpFakeIdent(jws, source, tokens, proto_info.name_token);
            for (proto_info.params) |param| {
                try dumpFakeIdent(jws, source, tokens, param);
            }
            try dumpAstNode(jws, source, tokens, ast, body);
        },
        .block => {
            const body = ast.extractExtras(node.data.extra_range);
            for (body) |i| {
                try dumpAstNode(jws, source, tokens, ast, @fromBackingInt(i));
            }
        },
        .@"while" => {
            const cond, const body = node.data.node_and_node;
            try dumpAstNode(jws, source, tokens, ast, cond);
            try dumpAstNode(jws, source, tokens, ast, body);
        },
        .if_simple, .if_full => {
            const info = frontend.Ast.info.ifAny(ast, node_index);

            try dumpAstNode(jws, source, tokens, ast, info.cond);
            try dumpAstNode(jws, source, tokens, ast, info.then_node);

            if (info.else_node.toIndex()) |else_node| {
                try dumpAstNode(jws, source, tokens, ast, else_node);
            }
        },
        .var_decl => {
            try dumpFakeIdent(jws, source, tokens, node.token + 1);
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .@"return" => {
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .unary => {
            try dumpAstNode(jws, source, tokens, ast, node.data.node);
        },
        .binary => {
            const lhs, const rhs = ast.nodeData(node_index).node_and_node;
            try dumpAstNode(jws, source, tokens, ast, lhs);
            try dumpAstNode(jws, source, tokens, ast, rhs);
        },
        .assign => {
            const dest, const src = ast.nodeData(node_index).node_and_node;
            try dumpAstNode(jws, source, tokens, ast, dest);
            try dumpAstNode(jws, source, tokens, ast, src);
        },
    }

    try jws.endArray();
    try jws.endObject();
}
