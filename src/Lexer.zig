const std = @import("std");

const Self = @This();

pub const Token = @import("lexer/Token.zig");

pub const Error = error{
    InvalidCharacter,
    NumberHasLeadingZero,
    UnterminatedMultilineComment,
};

source: []const u8,
offset: u32,

pub fn init(source: []const u8) Self {
    // should be checked while reading the file
    std.debug.assert(source.len <= std.math.maxInt(u32));

    return .{ .source = source, .offset = 0 };
}

pub fn recoverFromError(self: *Self, err: Error) void {
    switch (err) {
        error.InvalidCharacter => self.offset += 1,
        error.UnterminatedMultilineComment => self.offset = @intCast(self.source.len),
        error.NumberHasLeadingZero => self.skipWhile(std.ascii.isDigit),
    }
}

pub fn next(self: *Self) Error!?Token {
    try self.skipCommentsAndWhitespace();

    if (self.reachedEof()) {
        return null;
    }

    return self.singleCharTokens(&.{
        .{ ';', .semi },
        .{ '=', .assign },
        .{ '+', .plus },
        .{ '-', .minus },
        .{ '*', .asterisk },
        .{ '/', .slash },
        .{ '(', .lparen },
        .{ ')', .rparen },
    }) orelse
        try self.numbers() orelse
        self.identifiersAndKeywords(&.{
            .{ "val", .kw_val },
            .{ "var", .kw_var },
            .{ "return", .kw_return },
        }) orelse
        Error.InvalidCharacter;
}

pub fn tokenSpan(self: *Self, token: Token) struct { u32, u32 } {
    const len = switch (token.kind) {
        .semi, .assign, .plus, .minus, .asterisk, .slash, .lparen, .rparen => 1,
        .kw_val, .kw_var => 3,
        .kw_return => 6,
        .number => blk: {
            const prev_offset = self.offset;
            defer self.offset = prev_offset;

            self.offset = token.offset;
            self.skipWhile(std.ascii.isDigit);

            break :blk self.offset - prev_offset;
        },
        .ident => blk: {
            const prev_offset = self.offset;
            defer self.offset = prev_offset;

            self.offset = token.offset;
            self.skipWhile(isIdentifierChar);

            break :blk self.offset - prev_offset;
        },
    };

    return .{ token.offset, token.offset + len };
}

pub fn errorSpan(self: *Self, err: Error, offset: u32) struct { u32, u32 } {
    const len = switch (err) {
        error.InvalidCharacter => 1,
        error.NumberHasLeadingZero => blk: {
            const prev_offset = self.offset;
            defer self.offset = prev_offset;

            self.offset = offset;
            self.skipWhile(std.ascii.isDigit);

            break :blk self.offset - prev_offset;
        },
        error.UnterminatedMultilineComment => self.source.len - offset,
    };

    return .{ offset, offset + len };
}

pub fn lineColumnFromOffset(self: Self, offset: u32) struct { line: u32, column: u32 } {
    var line_start = if (offset != 0) offset - 1 else offset;
    while (line_start > 0) : (line_start -= 1) {
        if (self.get(line_start)) |c| {
            if (c == '\n') {
                line_start += 1;
                break;
            }
        }
    }

    return .{
        .line = @intCast(std.mem.countScalar(u8, self.source[0..@min(offset, self.source.len)], '\n') + 1),
        .column = offset - line_start + 1,
    };
}

fn singleCharTokens(self: *Self, comptime cs: []const struct { u8, Token.Kind }) ?Token {
    const peekedChar = self.peekChar().?;

    inline for (cs) |case| {
        const c, const kind = case;

        if (peekedChar == c) {
            defer _ = self.getChar();
            return Token{ .offset = self.offset, .kind = kind };
        }
    }

    return null;
}

fn numbers(self: *Self) !?Token {
    const peekedChar = self.peekChar().?;

    if (!std.ascii.isDigit(peekedChar)) {
        return null;
    }

    if (peekedChar != '0') {
        defer self.skipWhile(std.ascii.isDigit);
        return Token{ .kind = .number, .offset = self.offset };
    }

    if (self.peekCharAhead(1)) |nextChar| {
        if (std.ascii.isDigit(nextChar)) {
            return Error.NumberHasLeadingZero;
        }
    }

    _ = self.getChar();
    return Token{ .kind = .number, .offset = self.offset };
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn identifiersAndKeywords(self: *Self, comptime keywords: []const struct { []const u8, Token.Kind }) ?Token {
    const peekedChar = self.peekChar().?;

    if (!std.ascii.isAlphabetic(peekedChar) and peekedChar != '_') {
        return null;
    }

    const start = self.offset;
    self.skipWhile(isIdentifierChar);

    const identifier = self.source[start..self.offset];
    inline for (keywords) |case| {
        const kw, const kind = case;

        if (std.mem.eql(u8, kw, identifier)) {
            return Token{ .offset = start, .kind = kind };
        }
    }

    return Token{ .offset = start, .kind = .ident };
}

fn skipCommentsAndWhitespace(self: *Self) !void {
    while (true) {
        if (std.mem.eql(u8, "//", self.peekChars(2))) {
            self.skipUntil('\n');
            _ = self.getChar();
        } else if (std.mem.eql(u8, "/*", self.peekChars(2))) {
            const comment_end = std.mem.findPos(u8, self.source, self.offset + 2, "*/");

            if (comment_end) |end| {
                self.offset = @intCast(end + 2);
            } else {
                return Error.UnterminatedMultilineComment;
            }
        } else {
            if (std.ascii.isWhitespace(self.peekChar() orelse break)) {
                self.skipWhile(std.ascii.isWhitespace);
            } else break;
        }
    }
}

fn reachedEof(self: Self) bool {
    return self.offset >= self.source.len;
}

fn peekChar(self: Self) ?u8 {
    return self.get(self.offset);
}

fn peekCharAhead(self: Self, offset: u32) ?u8 {
    return self.get(self.offset + offset);
}

fn peekChars(self: Self, size: u32) []const u8 {
    const tail = self.source[self.offset..];
    return tail[0..@min(size, tail.len)];
}

fn getChar(self: *Self) ?u8 {
    defer self.offset += 1;
    return self.peekChar();
}

fn get(self: Self, offset: u32) ?u8 {
    if (offset >= self.source.len) {
        return null;
    }

    return self.source[offset];
}

fn skipUntil(self: *Self, comptime c: u8) void {
    const pos = std.mem.findScalarPos(u8, self.source, self.offset, c);
    self.offset = @intCast(pos orelse self.source.len);
}

fn skipWhile(self: *Self, comptime pred: fn (u8) bool) void {
    while (self.peekChar()) |c| {
        if (!pred(c)) {
            return;
        }
        _ = self.getChar();
    }
}
