const std = @import("std");

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub const TokenList = std.MultiArrayList(Token);

pub const Token = struct {
    pub const Index = u32;
    pub const MAX_IDENT_LEN = 255;

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
        kw_if,
        kw_else,
        kw_while,
        kw_break,
        kw_continue,
        kw_true,
        kw_false,
        semi,
        assign,
        plus,
        minus,
        asterisk,
        slash,
        bang,
        eq,
        ne,
        lt,
        le,
        gt,
        ge,
        logical_and,
        logical_or,
        lparen,
        rparen,
        lbrace,
        rbrace,

        pub fn isError(self: Kind) bool {
            return switch (self) {
                .err_invalid_character,
                .err_number_has_leading_zero,
                .err_unterminated_multiline_comment,
                => true,
                else => false,
            };
        }

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
                .kw_if => "`if`",
                .kw_else => "`else`",
                .kw_while => "`while`",
                .kw_continue => "`continue`",
                .kw_true => "`true`",
                .kw_false => "`false`",
                .kw_break => "`break`",
                .semi => "`;`",
                .assign => "`=`",
                .plus => "`+`",
                .minus => "`-`",
                .asterisk => "`*`",
                .slash => "`/`",
                .bang => "`!`",
                .eq => "`==`",
                .ne => "`!=`",
                .lt => "`<`",
                .gt => "`>`",
                .le => "`<=`",
                .ge => "`>=`",
                .logical_and => "`&&`",
                .logical_or => "`||`",
                .lbrace => "`{`",
                .lparen => "`(`",
                .rparen => "`)`",
                .rbrace => "`}`",
            };
        }
    };
};

pub fn tokenLen(source: []const u8, token: Token) u32 {
    return switch (token.kind) {
        .eof => 0,
        .semi, .assign, .plus, .minus, .asterisk, .slash, .lparen, .rparen, .lbrace, .rbrace, .bang, .gt, .lt => 1,
        .eq, .ne, .le, .ge, .logical_and, .logical_or => 2,
        .kw_val, .kw_var => 3,
        .kw_return => 6,
        .kw_if => 2,
        .kw_else => 4,
        .kw_while => 5,
        .kw_break => 5,
        .kw_continue => 8,
        .kw_true => 4,
        .kw_false => 5,
        .err_invalid_character => 1,
        .err_unterminated_multiline_comment => @as(u32, @intCast(source.len)) - token.offset,
        .number, .err_number_has_leading_zero => lenMatching(source[token.offset..], std.ascii.isDigit),
        .ident => lenMatching(source[token.offset..], isIdentifierChar),
    };
}

fn lenMatching(source: []const u8, comptime pred: fn (u8) bool) u32 {
    for (source, 0..) |c, i| {
        if (!pred(c)) {
            return @intCast(i);
        }
    }

    return @intCast(source.len);
}

fn TrieNode(comptime Result: type) type {
    return struct {
        key: u8,
        children: []const @This() = &.{},
        result: ?Result = null,
    };
}

fn runTrie(
    comptime Result: type,
    comptime layout: []const TrieNode(Result),
    input: []const u8,
) ?struct { result: Result, consumed: u32 } {
    if (input.len == 0) {
        return null;
    }

    const c = input[0];
    inline for (layout) |node| {
        if (node.key == c) {
            const result_opt = runTrie(Result, node.children, input[1..]);
            if (result_opt) |result| {
                return .{ .result = result.result, .consumed = result.consumed + 1 };
            } else if (node.result) |result| {
                return .{ .result = result, .consumed = 1 };
            }
        }
    }
    return null;
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
            std.debug.assert(token.kind.isError());
            return token;
        }

        if (self.reachedEof()) {
            return self.mkToken(.eof);
        }

        return self.symbolTokens() orelse
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
        self.skipWhile(std.ascii.isWhitespace);

        if (std.mem.eql(u8, "//", self.peekChars(2))) {
            self.skipUntil('\n');
            return self.skipCommentsAndWhitespace();
        } else if (std.mem.eql(u8, "/*", self.peekChars(2))) {
            const comment_end = std.mem.findPos(u8, self.source, self.offset + 2, "*/");

            if (comment_end) |end| {
                self.offset = @intCast(end + 2);
            } else {
                defer self.offset = @intCast(self.source.len);
                return self.mkToken(.err_unterminated_multiline_comment);
            }

            return self.skipCommentsAndWhitespace();
        }

        return null;
    }

    fn symbolTokens(self: *Self) ?Token {
        const trie_layout: []const TrieNode(Token.Kind) = &.{
            .{ .key = ';', .result = .semi },
            .{ .key = '+', .result = .plus },
            .{ .key = '-', .result = .minus },
            .{ .key = '*', .result = .asterisk },
            .{ .key = '/', .result = .slash },
            .{ .key = '(', .result = .lparen },
            .{ .key = ')', .result = .rparen },
            .{ .key = '{', .result = .lbrace },
            .{ .key = '}', .result = .rbrace },
            .{ .key = '=', .result = .assign, .children = &.{.{ .key = '=', .result = .eq }} },
            .{ .key = '<', .result = .lt, .children = &.{.{ .key = '=', .result = .le }} },
            .{ .key = '>', .result = .gt, .children = &.{.{ .key = '=', .result = .ge }} },
            .{ .key = '!', .result = .bang, .children = &.{.{ .key = '=', .result = .ne }} },
            .{ .key = '&', .children = &.{.{ .key = '&', .result = .logical_and }} },
            .{ .key = '|', .children = &.{.{ .key = '|', .result = .logical_or }} },
        };

        const result = runTrie(Token.Kind, trie_layout, self.source[self.offset..]) orelse return null;
        defer self.offset += result.consumed;
        return self.mkToken(result.result);
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
        const keywords = std.StaticStringMap(Token.Kind).initComptime(comptime init: {
            // for each `kw_<NAME>` case produce a pair `("<NAME>", .<NAME>)`

            const info: std.lang.Type.Enum = @typeInfo(Token.Kind).@"enum";
            var result: [info.field_names.len]struct { []const u8, Token.Kind } = undefined;
            var i: usize = 0;
            for (info.field_names, info.field_values) |field_name, field_value| {
                if (std.mem.cutPrefix(u8, field_name, "kw_")) |kw| {
                    result[i] = .{ kw, @fromBackingInt(field_value) };
                    i += 1;
                }
            }
            break :init result[0..i];
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
