const std = @import("std");

// General parser conventions:
//
// Errors are passed internally using Zig's error handling mechanism
// No parse error escapes parser by language error handling mechanism, only by reporting it to `ErrorBundle`
// Errors are reported by the creating side
//
// `parse*` methods return null if parsing failed and no tokens were consumed and error if parsing failed and at least a token was consumed
// `expect*` methods return error if parsing failed, token consumption does not matter

const Parser = @This();

const lex = @import("lex.zig");
const Ast = @import("Ast.zig");
const Source = @import("Source.zig");
const ErrorBundle = @import("ErrorBundle.zig");

const Token = lex.Token;
const Node = Ast.Node;

pub const Error = error{ParseError};
pub const NonParseError = ErrorBundle.ReportError;

gpa: std.mem.Allocator,
source: Source,
errors: *ErrorBundle,

token_index: Token.Index,
tokens: lex.TokenList,

/// All nodes to be passed to AST
nodes: Ast.NodeList,
/// Scratch buffer for building extras
///
/// Example: while parsing a block, we enter another block
/// Their extras ranges must not overlap, so we build the new extras in the scratch,
/// then copy it to extras, and only after the outer block ends, we add its contents into the extras
scratch: std.ArrayList(Node.Index),
/// Extra data to be passed to AST
extras: std.ArrayList(u32),

pub fn init(gpa: std.mem.Allocator, source: Source, tokens: lex.TokenList, errors: *ErrorBundle) Parser {
    return .{
        .gpa = gpa,
        .source = source,
        .errors = errors,
        .token_index = 0,
        .tokens = tokens,
        .nodes = .empty,
        .scratch = .empty,
        .extras = .empty,
    };
}

pub fn deinit(self: *Parser) void {
    self.scratch.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Parser) NonParseError!Ast {
    std.debug.assert(self.tokens.len > 0);

    _ = try self.addNode(.{ .kind = .root, .token = 0 });

    while (self.tokenKind(self.token_index) != .eof) {
        const stmt_opt = try self.parseStatement();

        if (stmt_opt) |stmt| {
            try self.scratch.append(self.gpa, stmt);
        } else {
            try self.reportUnexpected(self.tokenKind(self.token_index), .{"a statement"});
            try self.scratch.append(self.gpa, try self.addRecoveryNode());
            _ = self.nextToken();
            continue;
        }
    }

    self.nodes.items(.data)[@backingInt(Node.Index.root)] = .{ .extra_range = .{
        .begin = @fromBackingInt(@intCast(self.extras.items.len)),
        .end = @fromBackingInt(@intCast(self.extras.items.len + self.scratch.items.len)),
    } };
    try self.extras.appendSlice(self.gpa, @ptrCast(self.scratch.items));

    return .{
        .nodes = self.nodes.slice(),
        .extra_data = try self.extras.toOwnedSlice(self.gpa),
    };
}

fn addNode(self: *Parser, node: Node) !Node.Index {
    const result: u32 = @intCast(self.nodes.len);
    try self.nodes.append(self.gpa, node);
    return @fromBackingInt(result);
}

fn addRecoveryNode(self: *Parser) !Node.Index {
    return self.addNode(.{ .kind = .recovery, .token = self.token_index });
}

fn tokenKind(self: Parser, index: Token.Index) Token.Kind {
    return self.tokens.items(.kind)[index];
}

/// Eat a token if its `kind` is present in `kinds`. Returns index of the eaten token
fn eatTokenAny(self: *Parser, comptime kinds: []const Token.Kind) ?Token.Index {
    if (std.mem.findScalar(Token.Kind, kinds, self.tokenKind(self.token_index)) != null) {
        return self.nextToken();
    }
    return null;
}

/// Eat a token if its `kind` matches the given one. Returns index of the eaten token
fn eatToken(self: *Parser, comptime kind: Token.Kind) ?Token.Index {
    if (self.tokenKind(self.token_index) == kind) {
        return self.nextToken();
    }

    return null;
}

/// Advance current token index. Returns index of the next token
fn nextToken(self: *Parser) Token.Index {
    defer self.token_index += 1;
    return self.token_index;
}

/// Format a list of *things* into a readable "A, B, C, D or E". Accepts `Token.Kind`s or strings of any kind
inline fn formatExpectedList(comptime list: anytype) []const u8 {
    var result: []const u8 = "";

    const info = @typeInfo(@TypeOf(list)).@"struct";
    const fields = info.field_names.len;

    for (info.field_names, info.field_types, 0..) |field_name, field_type, i| {
        const value = @field(list, field_name);

        if (i > 0 and i + 2 < fields.len) {
            result = result ++ ", ";
        } else if (i > 0 and i + 1 < fields.len) {
            result = result ++ " or ";
        }

        result = result ++
            if (field_type == Token.Kind)
                value.toString()
            else switch (@typeInfo(field_type)) {
                .pointer => |field_info| switch (field_info.size) {
                    .one, .slice => @as([]const u8, value),
                    .many, .c => @as([:0]const u8, std.mem.span(value)),
                },
                .array => @as([]const u8, &value),
                else => @compileError("only `Token.Kind` and strings are supported for \"expected\" formatting"),
            };
    }

    return result;
}

fn report(self: *Parser, comptime fmt: []const u8, args: anytype) NonParseError!void {
    const cur_token = self.tokens.get(self.token_index);
    try self.errors.addMessage(self.source.spanByToken(cur_token), fmt, args);
    try self.errors.finishReport();
}

fn fail(self: *Parser, comptime fmt: []const u8, args: anytype) (Parser.Error || NonParseError) {
    try self.report(fmt, args);
    return Error.ParseError;
}

fn reportUnexpected(self: *Parser, actual: Token.Kind, comptime expected: anytype) NonParseError!void {
    switch (actual) {
        .err_invalid_character,
        .err_number_has_leading_zero,
        .err_unterminated_multiline_comment,
        => try self.report("{s}", .{actual.toString()}),
        else => try self.report(
            // NOTE:
            // if you `expect` a '}', this breaks
            // but that is avoidable
            "expected " ++ formatExpectedList(expected) ++ ", but got {s}",
            .{actual.toString()},
        ),
    }
}

fn failWithUnexpected(self: *Parser, actual: Token.Kind, comptime expected: anytype) (Parser.Error || NonParseError) {
    try self.reportUnexpected(actual, expected);
    return Error.ParseError;
}

fn expectToken(self: *Parser, comptime kind: Token.Kind) !Token.Index {
    if (self.tokenKind(self.token_index) != kind) {
        return self.failWithUnexpected(self.tokenKind(self.token_index), .{kind});
    }

    return self.nextToken();
}

/// Skip tokens until one with `kind` is seen, then also eat it
fn skipUntilInclusive(self: *Parser, comptime kind: Token.Kind) void {
    if (self.skipUntil(kind)) {
        _ = self.nextToken();
    }
}

/// Skip tokens until one with `kind` is seen
fn skipUntil(self: *Parser, comptime kind: Token.Kind) bool {
    if (std.mem.findScalarPos(
        Token.Kind,
        self.tokens.items(.kind),
        self.token_index,
        kind,
    )) |index| {
        self.token_index = @intCast(index);
        return true;
    } else {
        self.token_index = @intCast(self.tokens.len - 1);
        return false;
    }
}

/// Skip tokens until one with `kind` present in `kinds` is seen
fn skipUntilAny(self: *Parser, comptime kinds: []const Token.Kind) Token.Kind {
    if (std.mem.findAnyPos(
        Token.Kind,
        self.tokens.items(.kind),
        self.token_index,
        kinds,
    )) |index| {
        self.token_index = @intCast(index);
        return self.tokenKind(self.token_index);
    } else {
        self.token_index = @intCast(self.tokens.len - 1);
        std.debug.assert(self.tokenKind(self.token_index) == .eof);
        return .eof;
    }
}

fn expectStatement(self: *Parser) !Node.Index {
    return try self.parseStatement() orelse
        self.failWithUnexpected(
            self.tokenKind(self.token_index),
            .{"a statement"},
        );
}

/// Parse a statement. Eats semicolons for statements expecting one. Recovers from errors
fn parseStatement(self: *Parser) NonParseError!?Node.Index {
    return try self.parseStatementWithoutSemicolon() orelse
        self.parseStatementWithSemicolon() catch |err|
        if (err == error.ParseError) {
            defer self.skipUntilInclusive(.semi);
            return try self.addRecoveryNode();
        } else return @errorCast(err);
}

/// Parse a subclass of statements that expect a semicolon. Does no extra error recovery
fn parseStatementWithSemicolon(self: *Parser) !?Node.Index {
    const stmt = try self.parseSingleTokenNode(.kw_continue, .@"continue") orelse
        try self.parseSingleTokenNode(.kw_break, .@"break") orelse
        try self.parseVarDecl() orelse
        try self.parseReturn() orelse
        try self.parseAssignmentOrExpr();

    _ = try self.expectToken(.semi);
    return stmt;
}

/// Parse a subclas of statements that do not expect a semicolon. Recovers from errors
fn parseStatementWithoutSemicolon(self: *Parser) NonParseError!?Node.Index {
    return try self.parseBlock() orelse
        try self.parseIf() orelse
        try self.parseWhile();
}

/// Parse a node represented by a token of kind `token_kind`. Does no error recovery
fn parseSingleTokenNode(
    self: *Parser,
    comptime token_kind: Token.Kind,
    comptime node_kind: Node.Kind,
) !?Node.Index {
    return if (self.eatToken(token_kind)) |token_index|
        try self.addNode(.{ .kind = node_kind, .token = token_index })
    else
        null;
}

/// Parse a node represented by a token of kind, present in `tokens_kinds`. Does no extra error recovery
fn parseSingleTokenNodeAny(
    self: *Parser,
    comptime token_kinds: []const Token.Kind,
    comptime node_kind: Node.Kind,
) !?Node.Index {
    return if (self.eatTokenAny(token_kinds)) |token_index|
        try self.addNode(.{ .kind = node_kind, .token = token_index })
    else
        null;
}

/// Parse a variable declaration. Recovers from errors
fn parseVarDecl(self: *Parser) NonParseError!?Node.Index {
    const var_token = self.eatTokenAny(&.{ .kw_val, .kw_var }) orelse return null;

    _ = self.expectToken(.ident) catch try self.addRecoveryNode();

    const initNode = init: {
        _ = self.expectToken(.assign) catch {
            defer _ = self.skipUntil(.semi);
            break :init try self.addRecoveryNode();
        };

        break :init self.expectExpr() catch |err|
            if (err == error.ParseError) {
                defer _ = self.skipUntil(.semi);
                break :init try self.addRecoveryNode();
            } else return @errorCast(err);
    };

    return try self.addNode(.{
        .kind = .var_decl,
        .token = var_token,
        .data = .{ .node = initNode },
    });
}

/// Parse a return. Recovers from errors
fn parseReturn(self: *Parser) NonParseError!?Node.Index {
    const ret_token = self.eatToken(.kw_return) orelse return null;
    const retval = self.expectExpr() catch |err|
        if (err == error.ParseError) blk: {
            defer _ = self.skipUntil(.semi);
            break :blk try self.addRecoveryNode();
        } else return @errorCast(err);

    return try self.addNode(.{
        .kind = .@"return",
        .token = ret_token,
        .data = .{ .node = retval },
    });
}

/// Parse a block of statements. Recovers from errors
fn parseBlock(self: *Parser) NonParseError!?Node.Index {
    const brace_token = self.eatToken(.lbrace) orelse return null;

    const scratch_top = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch_top);

    while (self.eatToken(.rbrace) == null) {
        const stmt = self.expectStatement() catch |err|
            if (err == error.ParseError) recovery: {
                defer if (self.skipUntilAny(&.{ .semi, .rbrace }) == .semi) {
                    _ = self.nextToken();
                };
                break :recovery try self.addRecoveryNode();
            } else return @errorCast(err);
        try self.scratch.append(self.gpa, stmt);
    }

    const data: Ast.ExtraRange = .{
        .begin = @fromBackingInt(@intCast(self.extras.items.len)),
        .end = @fromBackingInt(@intCast(self.extras.items.len + self.scratch.items.len - scratch_top)),
    };

    try self.extras.appendSlice(self.gpa, @ptrCast(self.scratch.items[scratch_top..]));
    return try self.addNode(.{
        .kind = .block,
        .token = brace_token,
        .data = .{ .extra_range = data },
    });
}

/// Parse condition of an "if" or "while" (an expression in parentheses).
/// Differs from `parseParenExpr` in error recovery, suitable for "if" and "while"
fn parseCondition(self: *Parser) NonParseError!Node.Index {
    _ = self.expectToken(.lparen) catch {
        defer switch (self.skipUntilAny(&.{ .rparen, .lbrace, .semi, .rbrace })) {
            .rparen, .semi, .rbrace => _ = self.nextToken(),
            else => {},
        };
        return try self.addRecoveryNode();
    };

    const res = self.expectExpr() catch |err|
        if (err == error.ParseError) {
            defer switch (self.skipUntilAny(&.{ .rparen, .lbrace, .semi, .rbrace })) {
                .rparen, .semi, .rbrace => _ = self.nextToken(),
                else => {},
            };
            return try self.addRecoveryNode();
        } else return @errorCast(err);

    _ = self.expectToken(.rparen) catch {
        defer switch (self.skipUntilAny(&.{ .lbrace, .semi, .rbrace })) {
            .semi, .rbrace => _ = self.nextToken(),
            else => {},
        };
        return try self.addRecoveryNode();
    };
    return res;
}

/// Parse an "if" statement. Recovers from errors
fn parseIf(self: *Parser) NonParseError!?Node.Index {
    const kw_token = self.eatToken(.kw_if) orelse return null;

    const cond = try self.parseCondition();
    const then_node = self.expectStatement() catch |err|
        if (err == error.ParseError) recovery: {
            defer {
                _ = self.skipUntilAny(&.{ .semi, .rbrace });
                _ = self.nextToken();
            }
            break :recovery try self.addRecoveryNode();
        } else return @errorCast(err);

    if (self.eatToken(.kw_else) != null) {
        const else_node = self.expectStatement() catch |err|
            if (err == error.ParseError) recovery: {
                defer {
                    _ = self.skipUntilAny(&.{ .semi, .rbrace });
                    _ = self.nextToken();
                }
                break :recovery try self.addRecoveryNode();
            } else return @errorCast(err);

        const extra_index: Ast.ExtraIndex = @fromBackingInt(@intCast(self.extras.items.len));
        try self.extras.appendSlice(self.gpa, @ptrCast(&.{ then_node, else_node }));

        return try self.addNode(.{
            .kind = .if_full,
            .token = kw_token,
            .data = .{ .node_and_extra = .{ cond, extra_index } },
        });
    } else return try self.addNode(.{
        .kind = .if_simple,
        .token = kw_token,
        .data = .{ .node_and_node = .{ cond, then_node } },
    });
}

/// Parse a "while" statement. Recovers from errors
fn parseWhile(self: *Parser) NonParseError!?Node.Index {
    const kw_token = self.eatToken(.kw_while) orelse return null;

    const cond = try self.parseCondition();
    const body = self.expectStatement() catch |err|
        if (err == error.ParseError) recovery: {
            defer {
                _ = self.skipUntilAny(&.{ .semi, .rbrace });
                _ = self.nextToken();
            }
            break :recovery try self.addRecoveryNode();
        } else return @errorCast(err);

    return try self.addNode(.{
        .kind = .@"while",
        .token = kw_token,
        .data = .{ .node_and_node = .{ cond, body } },
    });
}

/// Try and eat a token representing an assignment operator
fn eatAssignmentOp(self: *Parser) ?Token.Index {
    return self.eatToken(.assign);
}

/// Parse an assignment statement or expression statement. Does no extra error recovery
fn parseAssignmentOrExpr(self: *Parser) !?Node.Index {
    const lhs = try self.parseExpr() orelse return null;

    const assignment_token = self.eatAssignmentOp() orelse return lhs;

    const rhs = try self.expectExpr();
    return try self.addNode(.{
        .kind = .assign,
        .token = assignment_token,
        .data = .{ .node_and_node = .{ lhs, rhs } },
    });
}

fn expectExpr(self: *Parser) !Node.Index {
    return try self.parseExpr() orelse
        self.failWithUnexpected(
            self.tokenKind(self.token_index),
            .{"an expression"},
        );
}

/// Parse an expression. Does no extra error recovery
fn parseExpr(self: *Parser) (Parser.Error || NonParseError)!?Node.Index {
    const lhs = try self.parseTerm() orelse return null;
    return try self.parseExprPrecedence(lhs, 0);
}

const Associativity = enum {
    none,
    left,
    right,
};

/// Try and peek a token representing a binary operator
fn peekBinaryOp(self: Parser) ?struct { token: Token.Index, precedence: u32, associativity: Associativity } {
    const kind = self.tokenKind(self.token_index);

    const precedence: u32, const associativity: Associativity = switch (kind) {
        .logical_or => .{ 0, .left },
        .logical_and => .{ 1, .left },
        .eq, .ne => .{ 2, .none },
        .lt, .gt, .le, .ge => .{ 3, .none },
        .plus, .minus => .{ 4, .left },
        .asterisk, .slash => .{ 5, .left },
        else => return null,
    };

    return .{ .token = self.token_index, .precedence = precedence, .associativity = associativity };
}

/// Parse a binary expression (if an operator is present). Does no extra error recovery
fn parseExprPrecedence(self: *Parser, initial_lhs: Node.Index, min_prec: u32) !Node.Index {
    var lhs = initial_lhs;

    while (true) {
        const op = self.peekBinaryOp() orelse break;
        if (op.precedence < min_prec) break;

        _ = self.nextToken();

        var rhs = try self.expectTerm();

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
            .data = .{ .node_and_node = .{ lhs, rhs } },
        });
    }

    return lhs;
}

fn expectTerm(self: *Parser) !Node.Index {
    return try self.parseTerm() orelse
        self.failWithUnexpected(
            self.tokenKind(self.token_index),
            .{"a term"},
        );
}

/// Try and eat a token representing a unary operator
fn eatUnaryOp(self: *Parser) ?Token.Index {
    return self.eatTokenAny(&.{ .minus, .bang });
}

/// Parse a term: `unary_expr`, `literal` or `(expr)`. Does no extra error recovery
fn parseTerm(self: *Parser) (Parser.Error || NonParseError)!?Node.Index {
    if (self.eatUnaryOp()) |unary_op| {
        const operand = try self.expectTerm();
        return try self.addNode(.{
            .kind = .unary,
            .token = unary_op,
            .data = .{ .node = operand },
        });
    }

    return try self.parseSingleTokenNodeAny(&.{ .kw_true, .kw_false }, .bool_literal) orelse
        try self.parseSingleTokenNode(.number, .number) orelse
        try self.parseSingleTokenNode(.ident, .name_ref) orelse
        try self.parseParenExpr();
}

/// Parse an expression in parentheses. Recovers from errors
fn parseParenExpr(self: *Parser) NonParseError!?Node.Index {
    _ = self.eatToken(.lparen) orelse return null;

    const res = self.expectExpr() catch |err|
        if (err == error.ParseError) {
            defer if (self.skipUntilAny(&.{ .rparen, .semi }) == .rparen) {
                _ = self.nextToken();
            };
            return try self.addRecoveryNode();
        } else return @errorCast(err);

    // used instead of `eatToken` only because of its error message
    _ = self.expectToken(.rparen) catch {};

    return res;
}
