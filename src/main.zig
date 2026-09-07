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
        printError(io, "Failed parsing arguments", err);
        return 2;
    };

    const source = readFile(io, gpa, args.path) catch |err| {
        printError(io, "Failed reading source file", err);
        return 1;
    };
    defer gpa.free(source);

    var lexer = spl.lex.Lexer.init(source);
    var tokens = lexer.run(gpa) catch |err| {
        printError(io, "Failed tokenizing", err);
        return 1;
    };
    defer tokens.deinit(gpa);

    if (args.tokens_dump_path) |dump_path| {
        dumpTokens(io, source, tokens, dump_path) catch |err|
            printError(io, "Failed dumping tokens", err);
    }

    // var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    // try stdout_writer.interface.print("Hello spl!\n", .{});
    // try stdout_writer.flush();

    return 0;
}

fn printError(io: std.Io, comptime msg: []const u8, err: anyerror) void {
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    stderr_writer.interface.print(msg ++ ": {s}\n", .{@errorName(err)}) catch {};
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

    try writer.interface.writeAll("[\n");

    for (0..tokens.len) |i| {
        if (i > 0) {
            try writer.interface.writeAll(",\n");
        }

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
            .err_invalid_character, .err_number_has_leading_zero, .err_unterminated_multiline_comment => "ERROR",
        };

        const error_msg = switch (token.kind) {
            .err_invalid_character => "invalid character",
            .err_number_has_leading_zero => "number has leading zero",
            .err_unterminated_multiline_comment => "unterminated multiline comment",
            else => null,
        };

        const loc = spl.lex.lineColumnFromOffset(source, token.offset);

        try std.json.fmt(.{ .kind = kind_name, .msg = error_msg, .line = loc.line, .column = loc.column }, .{})
            .format(&writer.interface);
    }

    try writer.interface.writeAll("\n]");
    try writer.flush();
}
