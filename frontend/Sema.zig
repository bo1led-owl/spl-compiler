const Self = @This();

const std = @import("std");
const lex = @import("lex.zig");
const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const ErrorBundle = @import("ErrorBundle.zig");

gpa: std.mem.Allocator,
source: Source,
tokens: lex.TokenList.Slice,
ast: Ast,
errors: *ErrorBundle,

/// Defined named entities
names: std.StringArrayHashMapUnmanaged(DeclarationInfo),
/// Because `vars` is an `ArrayHashMap`, we can use indices to keep track of scope stacking
scope_tops: std.ArrayList(u32),

inside_loop: bool,

const DeclarationInfo = union(enum) {
    param: lex.Token.Index,
    node: Ast.Node.Index,
};

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList.Slice,
    ast: Ast,
    errors: *ErrorBundle,
) Self {
    return .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .ast = ast,
        .errors = errors,
        .names = .empty,
        .scope_tops = .empty,
        .inside_loop = false,
    };
}

pub fn deinit(self: *Self) void {
    self.names.deinit(self.gpa);
    self.scope_tops.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    _ = try self.visitNode(.root);
}

fn enterScope(self: *Self) !void {
    try self.scope_tops.append(self.gpa, @intCast(self.names.entries.len));
}

fn leaveScope(self: *Self) void {
    const top = self.scope_tops.pop().?;
    self.names.shrinkRetainingCapacity(@intCast(top));
}

const NodeInfo = packed struct {
    // split into flags in case we get function pointers as variables

    is_assignable: bool = false,
    is_valid_lvalue_but_constant: bool = false,
    is_callable: bool = false,
    terminator_kind: TerminatorKind = .none,

    pub const TerminatorKind = enum(u2) {
        none = 0,
        any = 1,
        ret = 2,

        pub fn meet(a: TerminatorKind, b: TerminatorKind) TerminatorKind {
            return @fromBackingInt(@min(@backingInt(a), @backingInt(b)));
        }
    };

    pub fn isTerminator(self: NodeInfo) bool {
        return self.terminator_kind != .none;
    }

    pub const none: NodeInfo = .{};
    pub const assignable: NodeInfo = .{ .is_assignable = true };
    pub const valid_lvalue_but_constant: NodeInfo = .{ .is_valid_lvalue_but_constant = true };
    pub const terminator: NodeInfo = .{ .terminator_kind = .any };
    pub const @"return": NodeInfo = .{ .terminator_kind = .ret };
    pub const callable: NodeInfo = .{ .is_callable = true };
};

fn getDeclarationKind(self: Self, decl_info: DeclarationInfo) []const u8 {
    switch (decl_info) {
        .param => return "function parameter",
        .node => |decl_node_index| switch (self.ast.nodeKind(decl_node_index)) {
            .var_decl => {
                const mutability_token = self.tokenKindByNodeIndex(decl_node_index);
                const is_mutable = mutability_token == .kw_var;
                return if (is_mutable) "variable" else "constant";
            },
            .fn_proto => {
                const is_extern = Ast.info.fnProto(self.ast, self.tokens, decl_node_index).is_extern;
                return if (is_extern) "extern function" else "function";
            },
            else => unreachable, // TODO: extend when more entity kinds are added
        },
    }
}

fn reportRedeclaration(self: *Self, entry_index: usize, name_token: lex.Token.Index, prev: DeclarationInfo) !void {
    const name = self.source.tokenLiteral(self.tokens.get(name_token));
    const prev_kind = self.getDeclarationKind(prev);
    const defined_in_current_scope = entry_index >= self.scope_tops.last() orelse 0;

    if (defined_in_current_scope) {
        try self.errors.addMessage(
            self.source.spanByToken(self.tokens.get(name_token)),
            "redeclaration of {s} `{s}` in the same scope",
            .{ prev_kind, name },
        );
    } else {
        try self.errors.addMessage(
            self.source.spanByToken(self.tokens.get(name_token)),
            "declaration of `{s}` shadows {s} from outer scope",
            .{ name, prev_kind },
        );
    }

    const prev_decl_span = switch (prev) {
        .param => |token| self.source.spanByToken(self.tokens.get(token)),
        .node => |prev_index| self.spanByNode(prev_index),
    };
    try self.errors.addMessage(prev_decl_span, "previously declared here", .{});
    try self.errors.finishReport();
}

fn visitNode(self: *Self, node_index: Ast.Node.Index) ErrorBundle.ReportError!NodeInfo {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => return .assignable,
        .root => {
            const body: []const Ast.Node.Index = @ptrCast(self.ast.extractExtras(self.ast.nodeData(node_index).extra_range));

            for (body) |func| {
                const proto = switch (self.ast.nodeKind(func)) {
                    .fn_proto => func,
                    .fn_decl => self.ast.nodeData(func).node_and_node.@"0",
                    else => unreachable,
                };
                _ = try self.visitNode(proto);
            }

            for (body) |func| {
                if (self.ast.nodeKind(func) != .fn_decl) {
                    continue;
                }
                _ = try self.visitNode(func);
            }

            const seen_main = self.names.contains("main");
            if (!seen_main) {
                try self.errors.addMessage(self.spanByNode(.root), "no `main` function in the file", .{});
            }

            return .none;
        },
        .fn_proto => {
            const name_token_index = Ast.info.fnProto(self.ast, self.tokens, node_index).name_token;
            const name = self.source.tokenLiteral(self.tokens.get(name_token_index));

            const gop_res = try self.names.getOrPut(self.gpa, name);
            if (gop_res.found_existing) {
                try self.reportRedeclaration(gop_res.index, name_token_index, gop_res.value_ptr.*);
            } else {
                gop_res.value_ptr.* = .{ .node = node_index };
            }

            return .callable;
        },
        .fn_decl => {
            const proto, const body = self.ast.nodeData(node_index).node_and_node;

            try self.enterScope();
            defer self.leaveScope();

            const params = Ast.info.fnProto(self.ast, self.tokens, proto).params;
            for (params) |param| {
                const name_token = self.tokens.get(param);
                const name = self.source.tokenLiteral(name_token);
                const gop_res = try self.names.getOrPut(self.gpa, name);
                if (gop_res.found_existing) {
                    try self.reportRedeclaration(gop_res.index, param, gop_res.value_ptr.*);
                } else {
                    gop_res.value_ptr.* = .{ .param = param };
                }
            }

            const body_info = try self.visitNode(body);
            if (body_info.terminator_kind != .ret) {
                try self.errors.reportSingleMessage(
                    self.spanByNode(body),
                    "function implicitly returns",
                    .{},
                );
            }

            return .callable;
        },
        .block => {
            const body: []const Ast.Node.Index = @ptrCast(self.ast.extractExtras(self.ast.nodeData(node_index).extra_range));

            try self.enterScope();
            defer self.leaveScope();

            var terminator_body_index_opt: ?usize = null;
            var terminator_kind: NodeInfo.TerminatorKind = .none;
            for (body, 0..) |child_node_index, i| {
                const info = try self.visitNode(child_node_index);
                if (terminator_body_index_opt == null and info.isTerminator()) {
                    terminator_body_index_opt = i;
                    terminator_kind = info.terminator_kind;
                }
            }

            if (terminator_body_index_opt) |terminator_body_index| {
                const tail = body[terminator_body_index + 1 ..];
                if (tail.len != 0) {
                    const terminator_index: Ast.Node.Index = body[terminator_body_index];
                    const span: Source.Span = .{
                        .begin = self.spanByNode(tail[0]).begin,
                        .end = self.spanByNode(tail[tail.len - 1]).end,
                    };

                    try self.errors.addMessage(span, "unreachable code", .{});
                    try self.errors.addMessage(
                        self.spanByNode(terminator_index),
                        "control flow was diverted here",
                        .{},
                    );
                    try self.errors.finishReport();
                }
            }

            return if (terminator_body_index_opt != null)
                .{ .terminator_kind = terminator_kind }
            else
                .none;
        },
        .if_full, .if_simple => {
            const info = Ast.info.ifAny(self.ast, node_index);

            _ = try self.visitNode(info.cond);

            try self.enterScope();
            const then_info = try self.visitNode(info.then_node);
            self.leaveScope();

            if (info.else_node.toIndex()) |else_node| {
                try self.enterScope();
                const else_info = try self.visitNode(else_node);
                self.leaveScope();

                return .{ .terminator_kind = NodeInfo.TerminatorKind.meet(
                    then_info.terminator_kind,
                    else_info.terminator_kind,
                ) };
            } else {
                return .none;
            }
        },
        .@"while" => {
            const cond, const body = self.ast.nodeData(node_index).node_and_node;
            _ = try self.visitNode(cond);

            self.inside_loop = true;
            defer self.inside_loop = false;

            try self.enterScope();
            defer self.leaveScope();

            _ = try self.visitNode(body);

            return .none;
        },
        .@"continue" => {
            if (!self.inside_loop) {
                try self.errors.reportSingleMessage(self.spanByNode(node_index), "`continue` outside of a loop", .{});
            }
            return .terminator;
        },
        .@"break" => {
            if (!self.inside_loop) {
                try self.errors.reportSingleMessage(self.spanByNode(node_index), "`break` outside of a loop", .{});
            }
            return .terminator;
        },
        .var_decl => {
            const info = Ast.info.varDecl(self.ast, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const gop_res = try self.names.getOrPut(self.gpa, name);
            if (gop_res.found_existing) {
                try self.reportRedeclaration(gop_res.index, info.name_token, gop_res.value_ptr.*);
            } else {
                gop_res.value_ptr.* = .{ .node = node_index };
            }

            _ = try self.visitNode(self.ast.nodeData(node_index).node);

            return .none;
        },
        .name_ref => {
            const name_token = self.tokens.get(self.ast.nodeToken(node_index));
            const name = self.source.tokenLiteral(name_token);

            const decl_opt = self.names.get(name);
            if (decl_opt) |decl| {
                switch (decl) {
                    .param => return .assignable,
                    .node => |declaration| switch (self.ast.nodeKind(declaration)) {
                        .var_decl => {
                            const mutability_token = self.tokenKindByNodeIndex(declaration);
                            const is_mutable = mutability_token == .kw_var;
                            if (is_mutable) {
                                return .assignable;
                            }
                            return .valid_lvalue_but_constant;
                        },
                        .fn_decl, .fn_proto => return .callable,
                        else => unreachable, // TODO: extend when more entity kinds are added
                    },
                }
            } else {
                try self.errors.reportSingleMessage(
                    self.source.spanByToken(name_token),
                    "reference to undefined name `{s}`",
                    .{name},
                );
                return .assignable;
            }
        },
        .call => {
            const info = Ast.info.call(self.ast, node_index);
            const callee_info = try self.visitNode(info.callee);
            if (!callee_info.is_callable) {
                try self.errors.reportSingleMessage(
                    self.spanByNode(info.callee),
                    "expression is not assignable",
                    .{},
                );
            }

            for (info.args) |arg| {
                _ = try self.visitNode(arg);
            }

            return .none;
        },
        .bool_literal => return .none,
        .number => {
            const token = self.tokens.get(self.ast.nodeToken(node_index));

            const value = std.fmt.parseUnsigned(u64, self.source.tokenLiteral(token), 10) catch
                std.math.maxInt(u64); // greater than both |minInt(i64)| and maxInt(i64)

            if (value > std.math.maxInt(i64)) {
                try self.errors.reportSingleMessage(
                    self.spanByNode(node_index),
                    std.fmt.comptimePrint(
                        "integer literal out of [{d}, {d}] range",
                        .{ 0, std.math.maxInt(i64) },
                    ),
                    .{},
                );
            }

            return .none;
        },
        .@"return" => {
            _ = try self.visitNode(self.ast.nodeData(node_index).node);
            return .@"return";
        },
        .unary => {
            _ = try self.visitNode(self.ast.nodeData(node_index).node);
            return .none;
        },
        .binary => {
            const lhs, const rhs = self.ast.nodeData(node_index).node_and_node;
            _ = try self.visitNode(lhs);
            _ = try self.visitNode(rhs);
            return .none;
        },
        .assign => {
            const dest_index, const source_index = self.ast.nodeData(node_index).node_and_node;

            const dest_info = try self.visitNode(dest_index);

            if (dest_info.is_assignable) {
                // explicitly do nothing
            } else if (dest_info.is_valid_lvalue_but_constant) {
                const declaration_span = switch (self.ast.nodeKind(dest_index)) {
                    .name_ref => name_ref: {
                        const name_token = self.tokens.get(self.ast.nodeToken(dest_index));
                        const decl_info = self.names.get(self.source.tokenLiteral(name_token)).?;
                        break :name_ref switch (decl_info) {
                            .param => |token_index| self.source.spanByToken(self.tokens.get(token_index)),
                            .node => |decl_node| self.spanByNode(decl_node),
                        };
                    },
                    else => unreachable,
                };

                try self.errors.addMessage(self.spanByNode(dest_index), "cannot assign to constant", .{});
                try self.errors.addMessage(declaration_span, "declared as constant here", .{});
                try self.errors.finishReport();
            } else {
                try self.errors.reportSingleMessage(self.spanByNode(dest_index), "expression is not assignable", .{});
            }

            _ = try self.visitNode(source_index);

            return .none;
        },
    }
}

fn tokenKindByNodeIndex(self: Self, node_index: Ast.Node.Index) lex.Token.Kind {
    return self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
}

fn tokenOffsetByNodeIndex(self: Self, node_index: Ast.Node.Index) u32 {
    return self.tokens.items(.offset)[self.ast.nodeToken(node_index)];
}

fn spanByNode(self: *Self, node_index: Ast.Node.Index) Source.Span {
    return switch (self.ast.nodeKind(node_index)) {
        .root => unreachable,
        .fn_proto => fn_proto: {
            const first_token = self.tokens.get(self.ast.nodeToken(node_index));

            const info = Ast.info.fnProto(self.ast, self.tokens, node_index);

            const supposed_last_token_idx = if (info.params.len > 0)
                info.params[info.params.len - 1]
            else
                info.name_token + 2;

            const last_token = self.tokens.get(@min(supposed_last_token_idx, self.tokens.len - 1));
            break :fn_proto self.source.spanByTokens(first_token, last_token);
        },
        .fn_decl => .{
            .begin = self.tokenOffsetByNodeIndex(node_index),
            .end = self.spanByNode(self.ast.nodeData(node_index).node_and_node.@"1").end,
        },
        .var_decl => .{
            .begin = self.tokenOffsetByNodeIndex(node_index),
            .end = self.spanByNode(self.ast.nodeData(node_index).node).end,
        },
        .block => block_span: {
            const opening = self.tokenOffsetByNodeIndex(node_index);

            const data = self.ast.nodeData(node_index).extra_range;
            const body: []const Ast.Node.Index = @ptrCast(self.ast.extractExtras(data));
            const last_stmt_end = if (body.len == 0)
                opening
            else
                self.spanByNode(body[body.len - 1]).end;

            const end =
                (std.mem.findScalarPos(u8, self.source.text, last_stmt_end, '}') orelse last_stmt_end) + 1;

            break :block_span .{ .begin = opening, .end = @intCast(end) };
        },
        .recovery,
        .name_ref,
        .bool_literal,
        .number,
        .@"continue",
        .@"break",
        => self.source.spanByToken(self.tokens.get(self.ast.nodeToken(node_index))),
        .@"return",
        .unary,
        => .{
            .begin = self.tokenOffsetByNodeIndex(node_index),
            .end = self.spanByNode(self.ast.nodeData(node_index).node).end,
        },
        .@"while" => .{
            .begin = self.tokenOffsetByNodeIndex(node_index),
            .end = self.spanByNode(self.ast.nodeData(node_index).node_and_node.@"1").end,
        },
        .if_full, .if_simple => if_span: {
            const info = Ast.info.ifAny(self.ast, node_index);
            const last_child = info.else_node.toIndex() orelse info.then_node;
            break :if_span .{
                .begin = self.tokenOffsetByNodeIndex(node_index),
                .end = self.spanByNode(last_child).end,
            };
        },
        .binary, .assign => binary_span: {
            const lhs, const rhs = self.ast.nodeData(node_index).node_and_node;
            break :binary_span .{
                .begin = self.spanByNode(lhs).begin,
                .end = self.spanByNode(rhs).end,
            };
        },
        .call => call: {
            const info = Ast.info.call(self.ast, node_index);

            const opening = self.tokenOffsetByNodeIndex(node_index);
            const last_expr_end = if (info.args.len == 0)
                opening
            else
                self.spanByNode(info.args[info.args.len - 1]).end;

            const end =
                (std.mem.findScalarPos(u8, self.source.text, last_expr_end, ')') orelse last_expr_end) + 1;

            break :call .{
                .begin = self.spanByNode(info.callee).begin,
                .end = @intCast(end),
            };
        },
    };
}
