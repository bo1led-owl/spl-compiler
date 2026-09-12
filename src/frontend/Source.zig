const std = @import("std");

const Self = @This();

const lex = @import("lex.zig");

text: []const u8,

pub const Span = struct {
    begin: u32,
    end: u32,

    pub fn len(self: Span) u32 {
        return self.end - self.begin;
    }
};

pub const Location = struct {
    line: u32,
    column: u32,

    pub fn fromOffset(source: []const u8, offset: u32) Location {
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
};

pub fn tokenLen(self: Self, token: lex.Token) u32 {
    return lex.tokenLen(self.text, token);
}

pub fn tokenLiteral(self: Self, token: lex.Token) []const u8 {
    return self.text[token.offset..(token.offset + self.tokenLen(token))];
}

pub fn locationFromOffset(self: Self, offset: u32) Location {
    return Location.fromOffset(self.text, offset);
}

pub fn spanByToken(self: Self, token: lex.Token) Span {
    return self.spanByTokens(token, token);
}

pub fn spanByTokens(self: Self, first_token: lex.Token, last_token: lex.Token) Span {
    return .{
        .begin = first_token.offset,
        .end = last_token.offset + self.tokenLen(last_token),
    };
}
