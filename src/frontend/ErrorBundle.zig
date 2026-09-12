const std = @import("std");

const Self = @This();

const lex = @import("lex.zig");
const Source = @import("Source.zig");

pub const ReportError = std.Io.Writer.Error || std.mem.Allocator.Error;

pub const ErrorDetails = struct {
    msg_start: u32, // no `msg_end` because messages are null-terminated
    span: Source.Span,
};

errors: std.ArrayList(ErrorDetails),
msg_storage: std.ArrayList(u8),

pub const empty: Self = .{
    .errors = .empty,
    .msg_storage = .empty,
};

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.errors.deinit(gpa);
    self.msg_storage.deinit(gpa);
    self.* = undefined;
}

pub fn nonEmpty(self: Self) bool {
    return self.errors.items.len > 0;
}

pub fn report(
    self: *Self,
    gpa: std.mem.Allocator,
    span: Source.Span,
    comptime fmt: []const u8,
    args: anytype,
) ReportError!void {
    const msg_start = self.msg_storage.items.len;
    try self.msg_storage.print(gpa, fmt, args);
    try self.msg_storage.append(gpa, 0);

    try self.errors.append(gpa, .{
        .msg_start = @intCast(msg_start),
        .span = span,
    });
}

pub fn renderToStderr(
    self: Self,
    io: std.Io,
    source: []const u8,
    terminal_mode: ?std.Io.Terminal.Mode,
) !void {
    var buffer: [256]u8 = undefined;
    const stderr = try std.Io.lockStderr(io, &buffer, terminal_mode);
    defer std.Io.unlockStderr(io);

    self.renderToTerminal(source, stderr.terminal()) catch |err| switch (err) {
        error.WriteFailed => return stderr.file_writer.err.?,
        else => |e| return e,
    };
}

fn getNullTerminatedMsg(self: Self, err: ErrorDetails) [:0]const u8 {
    return @ptrCast(self.msg_storage.items[err.msg_start..]);
}

pub fn renderToTerminal(self: Self, source: []const u8, terminal: std.Io.Terminal) !void {
    for (self.errors.items) |err| {
        try terminal.setColor(.bold);
        try terminal.writer.print(
            // replace with actual filename sometime in the future
            "<source>:{d}: ",
            .{lex.lineIndexFromOffset(source, err.span.begin + 1)},
        );

        try terminal.setColor(.red);
        try terminal.writer.writeAll("error: ");

        try terminal.setColor(.white);
        try terminal.writer.print(
            "{s}",
            .{self.getNullTerminatedMsg(err)},
        );

        try terminal.setColor(.reset);
        try terminal.writer.writeByte('\n');

        try renderRelevant(terminal, source, err.span);
    }
}

fn findLineStart(source: []const u8, start: u32) u32 {
    if (start == 0) return 0;

    var result = if (start == source.len)
        start - 1
    else
        start - @intFromBool(source[start] == '\n');
    while (result > 0) : (result -= 1) {
        if (source[result] == '\n') {
            return result + 1;
        }
    }

    return result;
}

fn renderRelevant(terminal: std.Io.Terminal, source: []const u8, span: Source.Span) !void {
    const output_start: usize = findLineStart(source, span.begin);
    const output_end = std.mem.findScalarPos(u8, source, span.end, '\n') orelse source.len;

    var line_start = output_start;
    while (line_start < output_end) {
        const line_end = std.mem.findScalarPos(u8, source, line_start, '\n') orelse source.len;
        defer line_start = line_end + 1;

        const line = source[line_start..line_end];

        try terminal.writer.writeAll(line);
        try terminal.writer.writeByte('\n');

        const highlight_start = @max(
            span.begin,
            std.mem.findNonePos(u8, source, line_start, &std.ascii.whitespace) orelse line_start,
        );

        const highlight_end = @min(span.end, line_start + line.len);

        const spaces = highlight_start - line_start;
        try terminal.writer.splatByteAll(' ', spaces);
        try terminal.setColor(.green);

        var printed_caret = false;
        if (line_start <= span.begin) {
            try terminal.writer.writeByte('^');
            printed_caret = true;
        }

        const last_line = line_end >= span.end;

        const tildas = if (span.len() > 1)
            highlight_end - highlight_start - @intFromBool(printed_caret) - @intFromBool(last_line)
        else
            0;
        try terminal.writer.splatByteAll('~', tildas);

        if (last_line and span.len() > 1) {
            try terminal.writer.writeByte('^');
        }

        try terminal.writer.writeByte('\n');
        try terminal.setColor(.reset);
    }
}
