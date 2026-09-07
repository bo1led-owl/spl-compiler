const std = @import("std");

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub const Token = struct {
    pub const Kind = enum(u8) {
        eof,
        err_invalid_character,
        err_number_has_leading_zero,
        err_unterminated_multiline_comment,
        number,
        ident,
        kw_val,
        kw_var,
        kw_return,
        semi,
        assign,
        plus,
        minus,
        asterisk,
        slash,
        lparen,
        rparen,
    };

    kind: Kind,
    offset: u32,
};

pub const TokenList = std.MultiArrayList(Token);

pub const Span = struct { begin: u32, end: u32 };
pub const Location = struct { line: u32, column: u32 };

pub fn tokenLen(source: []const u8, token: Token) u32 {
    return switch (token.kind) {
        .semi, .assign, .plus, .minus, .asterisk, .slash, .lparen, .rparen => 1,
        .kw_val, .kw_var => 3,
        .kw_return => 6,
        .err_invalid_character => 1,
        .err_unterminated_multiline_comment => source.len - token.offset,
        .number, .err_number_has_leading_zero => lenMatching(source[token.offset..], std.ascii.isDigit),
        .ident => lenMatching(source[token.offset..], isIdentifierChar),
    };
}

pub fn tokenSpan(source: []const u8, token: Token) Span {
    return .{
        .begin = token.offset,
        .end = token.offset + tokenLen(source, token),
    };
}

pub fn lineColumnFromOffset(source: []const u8, offset: u32) Location {
    var loc: Location = .{ .line = 1, .column = 1 };

    for (0..offset) |i| {
        if (source[i] == '\n') {
            loc.line += 1;
            loc.column = 1;
        } else {
            loc.column += 1;
        }
    }

    return loc;
}

fn lenMatching(source: []const u8, comptime pred: fn (u8) bool) u32 {
    for (source, 0..) |c, i| {
        if (!pred(c)) {
            return @intCast(i);
        }
    }

    return @intCast(source.len);
}

pub const Lexer = struct {
    const Self = @This();

    source: []const u8,
    offset: u32,

    pub fn init(source: []const u8) Self {
        // should be checked while reading the file
        std.debug.assert(source.len <= std.math.maxInt(u32));

        return .{ .source = source, .offset = 0 };
    }

    pub fn run(self: *Self, gpa: std.mem.Allocator) !TokenList {
        var result: TokenList = .empty;

        while (true) {
            const token = self.next();
            try result.append(gpa, token);

            if (token.kind == .eof) {
                break;
            }
        }

        return result;
    }

    fn mkToken(self: Self, kind: Token.Kind) Token {
        return .{ .kind = kind, .offset = self.offset };
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
        self.offset += lenMatching(self.source[self.offset..], pred);
    }

    fn next(self: *Self) Token {
        if (self.skipCommentsAndWhitespace()) |token| {
            // error tokens only
            return token;
        }

        if (self.reachedEof()) {
            return self.mkToken(.eof);
        }

        return self.singleCharTokens() orelse
            self.numbers() orelse
            self.identifiersAndKeywords() orelse
            blk: {
                defer _ = self.getChar();
                break :blk self.mkToken(.err_invalid_character);
            };
    }

    fn skipCommentsAndWhitespace(self: *Self) ?Token {
        var running = true;
        while (running) {
            running = false;

            self.skipWhile(std.ascii.isWhitespace);

            if (std.mem.eql(u8, "//", self.peekChars(2))) {
                self.skipUntil('\n');
                _ = self.getChar();

                running = true;
            } else if (std.mem.eql(u8, "/*", self.peekChars(2))) {
                const comment_end = std.mem.findPos(u8, self.source, self.offset + 2, "*/");

                if (comment_end) |end| {
                    self.offset = @intCast(end + 2);
                } else {
                    defer self.offset = @intCast(self.source.len);
                    return self.mkToken(.err_unterminated_multiline_comment);
                }

                running = true;
            }
        }

        return null;
    }

    fn singleCharTokens(self: *Self) ?Token {
        const tokens = &.{
            .{ ';', .semi },
            .{ '=', .assign },
            .{ '+', .plus },
            .{ '-', .minus },
            .{ '*', .asterisk },
            .{ '/', .slash },
            .{ '(', .lparen },
            .{ ')', .rparen },
        };

        const peekedChar = self.peekChar().?;

        inline for (tokens) |case| {
            const c, const kind = case;

            if (peekedChar == c) {
                defer _ = self.getChar();
                return Token{ .offset = self.offset, .kind = kind };
            }
        }

        return null;
    }

    fn numbers(self: *Self) ?Token {
        const peekedChar = self.peekChar().?;

        if (!std.ascii.isDigit(peekedChar)) {
            return null;
        }

        defer self.skipWhile(std.ascii.isDigit);

        if (peekedChar == '0') {
            const next_char_opt = self.peekCharAhead(1);
            if (next_char_opt != null and std.ascii.isDigit(next_char_opt.?)) {
                return Token{ .kind = .err_number_has_leading_zero, .offset = self.offset };
            }
        }

        return Token{ .kind = .number, .offset = self.offset };
    }

    fn identifiersAndKeywords(self: *Self) ?Token {
        const keywords = &.{
            .{ "val", .kw_val },
            .{ "var", .kw_var },
            .{ "return", .kw_return },
        };

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
                return Token{ .kind = kind, .offset = start };
            }
        }

        return Token{ .kind = .ident, .offset = start };
    }
};
