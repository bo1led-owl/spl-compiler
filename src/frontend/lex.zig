const std = @import("std");

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub const TokenList = std.MultiArrayList(Token);

pub const Token = struct {
    pub const Index = u32;

    kind: Kind,
    offset: u32,

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

        pub fn toString(self: Kind) []const u8 {
            return switch (self) {
                .eof => "EOF",
                .err_invalid_character => "invalid character",
                .err_number_has_leading_zero => "number has leading zero",
                .err_unterminated_multiline_comment => "unterminated multiline comment",
                .number => "a number",
                .ident => "an identifier",
                .kw_val => "`val`",
                .kw_var => "`var`",
                .kw_return => "`return`",
                .semi => "`;`",
                .assign => "`=`",
                .plus => "`+`",
                .minus => "`-`",
                .asterisk => "`*`",
                .slash => "`/`",
                .lparen => "`(`",
                .rparen => "`)`",
            };
        }
    };
};

pub fn tokenLen(source: []const u8, token: Token) u32 {
    return switch (token.kind) {
        .eof => 0,
        .semi, .assign, .plus, .minus, .asterisk, .slash, .lparen, .rparen => 1,
        .kw_val, .kw_var => 3,
        .kw_return => 6,
        .err_invalid_character => 1,
        .err_unterminated_multiline_comment => @as(u32, @intCast(source.len)) - token.offset,
        .number, .err_number_has_leading_zero => lenMatching(source[token.offset..], std.ascii.isDigit),
        .ident => lenMatching(source[token.offset..], isIdentifierChar),
    };
}

pub fn tokenLiteral(source: []const u8, token: Token) []const u8 {
    return source[token.offset..(token.offset + tokenLen(source, token))];
}

pub fn lineIndexFromOffset(source: []const u8, offset: u32) u32 {
    return @intCast(std.mem.countScalar(u8, source[0..offset], '\n'));
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

    pub fn next(self: *Self) Token {
        if (self.skipCommentsAndWhitespace()) |token| {
            std.debug.assert(token.kind == .err_invalid_character or
                token.kind == .err_number_has_leading_zero or
                token.kind == .err_unterminated_multiline_comment);
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

    fn mkToken(self: Self, kind: Token.Kind) Token {
        return .{ .kind = kind, .offset = self.offset };
    }

    fn reachedEof(self: Self) bool {
        return self.offset >= self.source.len;
    }

    fn peekChar(self: Self) ?u8 {
        return self.charAt(self.offset);
    }

    fn peekCharAhead(self: Self, offset: u32) ?u8 {
        return self.charAt(self.offset + offset);
    }

    fn peekChars(self: Self, size: u32) []const u8 {
        const tail = self.source[self.offset..];
        return tail[0..@min(size, tail.len)];
    }

    fn getChar(self: *Self) ?u8 {
        defer self.offset += 1;
        return self.peekChar();
    }

    fn charAt(self: Self, offset: u32) ?u8 {
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
        const peekedChar = self.peekChar().?;

        const kind: Token.Kind = switch (peekedChar) {
            ';' => .semi,
            '=' => .assign,
            '+' => .plus,
            '-' => .minus,
            '*' => .asterisk,
            '/' => .slash,
            '(' => .lparen,
            ')' => .rparen,
            else => return null,
        };

        defer _ = self.getChar();
        return self.mkToken(kind);
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
                return self.mkToken(.err_number_has_leading_zero);
            }
        }

        return self.mkToken(.number);
    }

    fn identifiersAndKeywords(self: *Self) ?Token {
        const keywords = std.StaticStringMap(Token.Kind).initComptime(&.{
            .{ "val", .kw_val },
            .{ "var", .kw_var },
            .{ "return", .kw_return },
        });

        const peekedChar = self.peekChar().?;

        if (!std.ascii.isAlphabetic(peekedChar) and peekedChar != '_') {
            return null;
        }

        const start = self.offset;
        self.skipWhile(isIdentifierChar);

        const identifier = self.source[start..self.offset];
        if (keywords.get(identifier)) |kind| {
            return Token{ .kind = kind, .offset = start };
        }

        return Token{ .kind = .ident, .offset = start };
    }
};
