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
        printError(io, "Error parsing arguments", err);
        return 2;
    };

    const input_file = readFile(io, gpa, args.path) catch |err| {
        printError(io, "Error reading source file", err);
        return 1;
    };
    defer gpa.free(input_file);

    var lexer = spl.Lexer.init(input_file);

    if (args.tokens_dump_path) |dump_path| {
        dumpTokens(io, &lexer, dump_path) catch |err|
            printError(io, "Error dumping tokens", err);
        lexer = spl.Lexer.init(input_file);
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

fn dumpTokens(io: std.Io, lexer: *spl.Lexer, path: []const u8) !void {
    const dump_file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer dump_file.close(io);

    var writer = dump_file.writer(io, &dump_buffer);

    try writer.interface.writeAll("[\n");

    var first = true;

    while (true) {
        if (!first) {
            try writer.interface.writeAll(",\n");
        }
        first = false;

        const token_opt = lexer.next() catch |err| {
            const loc = lexer.lineColumnFromOffset(lexer.offset);
            try std.json.fmt(.{ .kind = "ERROR", .err = err, .line = loc.line, .column = loc.column }, .{})
                .format(&writer.interface);
            lexer.recoverFromError(err);
            continue;
        };

        if (token_opt) |token| {
            const kind_name = switch (token.kind) {
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
            };
            const loc = lexer.lineColumnFromOffset(token.offset);
            try std.json.fmt(.{ .kind = kind_name, .line = loc.line, .column = loc.column }, .{})
                .format(&writer.interface);
        } else {
            break;
        }
    }

    const loc = lexer.lineColumnFromOffset(@intCast(lexer.source.len));
    try std.json.fmt(.{ .kind = "EOF", .line = loc.line, .column = loc.column }, .{})
        .format(&writer.interface);

    try writer.interface.writeAll("\n]");
    try writer.flush();
}
