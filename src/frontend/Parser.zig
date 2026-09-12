const std = @import("std");

// General parser conventions:
//
// Errors are passed internally using Zig's error handling mechanism
// No parse error escapes parser by language error handling mechanism, only by reporting it to `ErrorBundle`
// Errors are reported by the creating side
//
// `parse*` methods return null if parsing failed and no tokens were consumed and error if parsing failed and at least a token was consumed
// `expect*` methods return error if parsing failed, token consumption does not matter

const lex = @import("lex.zig");
const Ast = @import("Ast.zig");
const ErrorBundle = @import("ErrorBundle.zig");

const Self = @This();

const Token = lex.Token;
const TokenIndex = Ast.TokenIndex;

const Node = Ast.Node;

pub const Error = error{ParseError};

gpa: std.mem.Allocator,
source: []const u8,
errors: *ErrorBundle,

token_idx: TokenIndex,
tokens: lex.TokenList,

nodes: Ast.NodeList,
scratch: std.ArrayList(Node.Index),
extras: std.ArrayList(u32),

pub fn init(gpa: std.mem.Allocator, source: []const u8, tokens: lex.TokenList, errors: *ErrorBundle) Self {
    return .{
        .gpa = gpa,
        .source = source,
        .errors = errors,
        .token_idx = 0,
        .tokens = tokens,
        .nodes = .empty,
        .scratch = .empty,
        .extras = .empty,
    };
}

pub fn parse(self: *Self) (std.mem.Allocator.Error || std.Io.Writer.Error)!Ast {
    std.debug.assert(self.tokens.len > 0);

    defer self.scratch.deinit(self.gpa);

    _ = try self.addNode(.{ .kind = .root, .token = 0 });

    while (self.tokenKind(self.token_idx) != .eof) {
        const stmt_opt = self.parseStatement() catch |err|
            switch (err) {
                error.ParseError => {
                    self.skipUntilInclusive(.semi);
                    continue;
                },
                else => |e| return e,
            };

        if (stmt_opt) |stmt| {
            // later scratch will become useful when we will have many nested things
            // that contain N nodes inside
            try self.scratch.append(self.gpa, stmt);
        } else {
            try self.reportUnexpected(
                self.tokenKind(self.token_idx),
                .{"a statement"},
            );
            _ = self.nextToken();
            continue;
        }

        _ = self.expectToken(.semi) catch self.skipUntilInclusive(.semi);
    }

    _ = self.expectToken(.eof) catch {};

    self.nodes.items(.data)[@intFromEnum(Node.Index.root)] = .{ .extra_range = .{
        .begin = @intCast(self.extras.items.len),
        .end = @intCast(self.extras.items.len + self.scratch.items.len),
    } };

    try self.extras.appendSlice(self.gpa, @ptrCast(self.scratch.items));

    return .{
        .nodes = self.nodes,
        .extra_data = try self.extras.toOwnedSlice(self.gpa),
    };
}

fn addNode(self: *Self, node: Node) !Node.Index {
    const result: u32 = @intCast(self.nodes.len);
    try self.nodes.append(self.gpa, node);
    return @enumFromInt(result);
}

fn tokenKind(self: Self, idx: TokenIndex) Token.Kind {
    return self.tokens.items(.kind)[idx];
}

fn eatToken(self: *Self, kind: Token.Kind) ?TokenIndex {
    if (self.tokenKind(self.token_idx) == kind) {
        return self.nextToken();
    }

    return null;
}

fn nextToken(self: *Self) TokenIndex {
    defer self.token_idx += 1;
    return self.token_idx;
}

inline fn formatExpectedList(comptime list: anytype) []const u8 {
    var result: []const u8 = "";

    const fields = std.meta.fields(@TypeOf(list));

    for (0..fields.len) |i| {
        const field = fields[i];
        const value = @field(list, field.name);

        if (i > 0 and i + 2 < fields.len) {
            result = result ++ ", ";
        } else if (i > 0 and i + 1 < fields.len) {
            result = result ++ " or ";
        }

        result = result ++
            if (field.type == Token.Kind)
                value.toString()
            else switch (@typeInfo(field.type)) {
                .pointer => |info| switch (info.size) {
                    .one, .slice => @as([]const u8, value),
                    .many, .c => @as([:0]const u8, std.mem.span(value)),
                },
                .array => @as([]const u8, &value),
                else => @compileError("only `Token.Kind` and strings are supported for \"expected\" formatting"),
            };
    }

    return result;
}

fn report(self: *Self, comptime fmt: []const u8, args: anytype) ErrorBundle.ReportError!void {
    const cur_token = self.tokens.get(self.token_idx);
    try self.errors.report(
        .{ .begin = cur_token.offset, .end = cur_token.offset + lex.tokenLen(self.source, cur_token) },
        fmt,
        args,
    );
}

fn fail(self: *Self, comptime fmt: []const u8, args: anytype) (ErrorBundle.ReportError || Error) {
    try self.report(fmt, args);
    return Error.ParseError;
}

fn reportUnexpected(self: *Self, actual: Token.Kind, comptime expected: anytype) ErrorBundle.ReportError!void {
    switch (actual) {
        .err_invalid_character,
        .err_number_has_leading_zero,
        .err_unterminated_multiline_comment,
        => try self.report("{s}", .{actual.toString()}),
        else => try self.report(
            "expected " ++ formatExpectedList(expected) ++ ", but got {s}",
            .{actual.toString()},
        ),
    }
}

fn failWithUnexpected(self: *Self, actual: Token.Kind, comptime expected: anytype) (ErrorBundle.ReportError || Error) {
    try self.reportUnexpected(actual, expected);
    return Error.ParseError;
}

fn expectToken(self: *Self, comptime kind: Token.Kind) !TokenIndex {
    if (self.tokenKind(self.token_idx) != kind) {
        return self.failWithUnexpected(self.tokenKind(self.token_idx), .{kind});
    }

    return self.nextToken();
}

fn parseStatement(self: *Self) !?Node.Index {
    return try self.parseVarDecl() orelse
        try self.parseReturn() orelse
        try self.parseAssignmentOrExpr();
}

fn skipUntilInclusive(self: *Self, kind: Token.Kind) void {
    if (self.skipUntil(kind)) {
        _ = self.nextToken();
    }
}

fn skipUntil(self: *Self, kind: Token.Kind) bool {
    if (std.mem.findScalarPos(
        Token.Kind,
        self.tokens.items(.kind),
        self.token_idx,
        kind,
    )) |idx| {
        self.token_idx = @intCast(idx);
        return true;
    } else {
        self.token_idx = @intCast(self.tokens.len - 1);
        return false;
    }
}

fn skipUntilAny(self: *Self, kinds: []const Token.Kind) Token.Kind {
    if (std.mem.findAnyPos(
        Token.Kind,
        self.tokens.items(.kind),
        self.token_idx,
        kinds,
    )) |idx| {
        self.token_idx = @intCast(idx);
        return self.tokenKind(self.token_idx);
    } else {
        self.token_idx = @intCast(self.tokens.len - 1);
        std.debug.assert(self.tokenKind(self.token_idx) == .eof);
        return .eof;
    }
}

fn parseVarDecl(self: *Self) !?Node.Index {
    const var_token = self.eatToken(.kw_val) orelse
        self.eatToken(.kw_var) orelse
        return null;

    _ = try self.expectToken(.ident);
    _ = try self.expectToken(.assign);

    const initNode = try self.expectExpr();

    return try self.addNode(.{
        .kind = .var_decl,
        .token = var_token,
        .data = .{ .node = initNode },
    });
}

fn parseReturn(self: *Self) !?Node.Index {
    const ret_token = self.eatToken(.kw_return) orelse return null;
    const retval = try self.expectExpr();

    return try self.addNode(.{
        .kind = .@"return",
        .token = ret_token,
        .data = .{ .node = retval },
    });
}

fn assignmentNodeKind(token: Token.Kind) ?Node.Kind {
    // to be expanded when `+=`, `-=` and similar appear
    return switch (token) {
        .assign => .assign,
        else => null,
    };
}

fn parseAssignmentOrExpr(self: *Self) !?Node.Index {
    const lhs = try self.parseExpr() orelse return null;

    const node_kind = assignmentNodeKind(self.tokenKind(self.token_idx)) orelse return lhs;
    const token = self.nextToken();

    const rhs = try self.expectExpr();

    return try self.addNode(.{
        .kind = node_kind,
        .token = token,
        .data = .{ .node_node = .{ lhs, rhs } },
    });
}

fn expectExpr(self: *Self) !Node.Index {
    return try self.parseExpr() orelse
        self.failWithUnexpected(
            self.tokenKind(self.token_idx),
            .{"an expression"},
        );
}

fn parseExpr(self: *Self) (Error || ErrorBundle.ReportError)!?Node.Index {
    const lhs = try self.parseTerm() orelse return null;
    return try self.parseExprPrecedence(lhs, 0);
}

const Associativity = enum {
    none,
    left,
    right,
};

fn peekBinaryOp(self: Self) ?struct { token: TokenIndex, precedence: u32, associativity: Associativity } {
    const kind = self.tokenKind(self.token_idx);

    const prec: u32, const assoc: Associativity = switch (kind) {
        .plus, .minus => .{ 0, .left },
        .asterisk, .slash => .{ 1, .left },
        else => return null,
    };

    return .{ .token = self.token_idx, .precedence = prec, .associativity = assoc };
}

fn parseExprPrecedence(self: *Self, initial_lhs: Node.Index, min_prec: u32) !Node.Index {
    var lhs = initial_lhs;

    while (true) {
        const op = self.peekBinaryOp() orelse break;
        if (op.precedence < min_prec) break;

        _ = self.nextToken();

        var rhs = try self.expectExpr();

        while (true) {
            const next_op = self.peekBinaryOp() orelse break;
            if (op.associativity == .none and next_op.associativity == .none and op.precedence == next_op.precedence) {
                return self.fail("cannot chain non-associative operators with same precedence", .{});
            }
            if (!(next_op.precedence > op.precedence or
                (next_op.associativity == .right and next_op.precedence == op.precedence)))
                break;

            rhs = try self.parseExprPrecedence(rhs, next_op.precedence);
        }

        lhs = try self.addNode(.{
            .kind = .binary,
            .token = op.token,
            .data = .{ .node_node = .{ lhs, rhs } },
        });
    }

    return lhs;
}

fn expectTerm(self: *Self) !Node.Index {
    return try self.parseTerm() orelse
        self.failWithUnexpected(
            self.tokenKind(self.token_idx),
            .{"a term"},
        );
}

fn eatUnaryOp(self: *Self) ?TokenIndex {
    return self.eatToken(.minus);
}

fn parseTerm(self: *Self) (Error || ErrorBundle.ReportError)!?Node.Index {
    const unary_op = self.eatUnaryOp();

    if (unary_op) |op| {
        const operand = try self.expectTerm();

        return switch (self.tokenKind(op)) {
            .minus => try self.addNode(.{
                .kind = .unary,
                .token = op,
                .data = .{ .node = operand },
            }),
            else => unreachable,
        };
    }

    return try self.parseNumber() orelse
        try self.parseNameRef() orelse
        try self.parseParenExpr();
}

fn parseNumber(self: *Self) !?Node.Index {
    const tok = self.eatToken(.number) orelse return null;
    return try self.addNode(.{ .kind = .number, .token = tok });
}

fn parseNameRef(self: *Self) !?Node.Index {
    const tok = self.eatToken(.ident) orelse return null;
    return try self.addNode(.{ .kind = .name_ref, .token = tok });
}

fn parseParenExpr(self: *Self) !?Node.Index {
    _ = self.eatToken(.lparen) orelse return null;
    const res = try self.expectExpr();
    _ = try self.expectToken(.rparen);
    return res;
}
