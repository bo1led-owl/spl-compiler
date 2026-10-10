const std = @import("std");

const Self = @This();

const lex = @import("lex.zig");
const Source = @import("Source.zig");

pub const ReportError = std.mem.Allocator.Error;

const MessageIndex = enum(u32) { _ };
const MessageStart = enum(u32) { invalid = std.math.maxInt(u32), _ };

const Message = struct {
    msg_start: MessageStart, // no `msg_end` because messages are null-terminated
    span: Source.Span,

    pub fn isNullMsg(self: Message) bool {
        return self.msg_start == .invalid;
    }
};

const null_msg: Message = .{ .msg_start = .invalid, .span = undefined };

gpa: std.mem.Allocator,
/// messages are populated by `null_msg`-terminated slices,
/// the first message of each slice is considered the error message,
/// the latter ones are considered note messages
messages: std.ArrayList(Message),
text_storage: std.ArrayList(u8),

pub fn init(gpa: std.mem.Allocator) Self {
    return .{
        .gpa = gpa,
        .messages = .empty,
        .text_storage = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.messages.deinit(self.gpa);
    self.text_storage.deinit(self.gpa);
    self.* = undefined;
}

pub fn nonEmpty(self: Self) bool {
    return self.messages.items.len > 0;
}

pub fn addMessage(
    self: *Self,
    span: Source.Span,
    comptime fmt: []const u8,
    args: anytype,
) ReportError!void {
    const msg_start = self.text_storage.items.len;
    try self.text_storage.print(self.gpa, fmt, args);
    try self.text_storage.append(self.gpa, 0);

    try self.messages.append(self.gpa, .{
        .msg_start = @fromBackingInt(@intCast(msg_start)),
        .span = span,
    });
}

pub fn finishReport(self: *Self) !void {
    try self.messages.append(self.gpa, null_msg);
}

pub fn renderToStderr(
    self: Self,
    io: std.Io,
    source: Source,
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

pub fn renderToTerminal(self: Self, source: Source, terminal: std.Io.Terminal) !void {
    var is_main_msg = true;
    for (self.messages.items) |msg| {
        if (msg.isNullMsg()) {
            is_main_msg = true;
            continue;
        }

        try terminal.setColor(.bold);

        const loc = source.locationFromOffset(msg.span.begin);
        try terminal.writer.print("{s}:{d}:{d} ", .{ source.filename, loc.line, loc.column });

        if (is_main_msg) {
            is_main_msg = false;
            try terminal.setColor(.red);
            try terminal.writer.writeAll("error: ");
        } else {
            try terminal.setColor(.cyan);
            try terminal.writer.writeAll("note: ");
        }

        const null_terminated_msg: [*:0]const u8 = @ptrCast(self.text_storage.items[@backingInt(msg.msg_start)..]);
        try terminal.setColor(.white);
        try terminal.writer.writeAll(std.mem.span(null_terminated_msg));

        try terminal.setColor(.reset);
        try terminal.writer.writeByte('\n');

        try renderRelevant(terminal, source.text, msg.span);
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

    var line_start = output_start;
    while (line_start <= span.end) {
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

        const tildas = if (span.len() > 1 and highlight_end != highlight_start)
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
