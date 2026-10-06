const Self = @This();

const std = @import("std");
const lex = @import("lex.zig");
const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const ErrorBundle = @import("ErrorBundle.zig");

gpa: std.mem.Allocator,
source: Source,
tokens: lex.TokenList,
ast: Ast,
errors: *ErrorBundle,
vars: std.StringArrayHashMapUnmanaged(struct { mut: bool }),
scope_tops: std.ArrayList(u32),
inside_loop: bool,

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList,
    ast: Ast,
    errors: *ErrorBundle,
) Self {
    return .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .ast = ast,
        .errors = errors,
        .vars = .empty,
        .scope_tops = .empty,
        .inside_loop = false,
    };
}

pub fn deinit(self: *Self) void {
    self.vars.deinit(self.gpa);
    self.scope_tops.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    _ = try self.visitNode(.root);
}

fn report(self: *Self, span: Source.Span, comptime fmt: []const u8, args: anytype) ErrorBundle.ReportError!void {
    try self.errors.report(self.gpa, span, fmt, args);
}

const NodeInfo = packed struct(u1) {
    is_assignable: bool = false,
};

fn enterScope(self: *Self) !void {
    try self.scope_tops.append(self.gpa, @intCast(self.vars.entries.len));
}

fn leaveScope(self: *Self) void {
    const top = self.scope_tops.pop().?;
    self.vars.shrinkRetainingCapacity(@intCast(top));
}

fn visitNode(self: *Self, node_index: Ast.Node.Index) (std.mem.Allocator.Error || ErrorBundle.ReportError)!NodeInfo {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => return .{},
        .root => {
            const body = self.ast.extractExtras(self.ast.nodeData(node_index).extra_range);
            if (body.len == 0) {
                try self.report(
                    self.spanByNode(node_index),
                    "empty program, at least one statement expected",
                    .{},
                );
                return .{};
            }

            for (body) |i| {
                _ = try self.visitNode(@fromBackingInt(i));
            }

            const last_node = self.ast.nodes.get(body[body.len - 1]);
            if (last_node.kind != .@"return") {
                try self.report(
                    self.spanByNode(@fromBackingInt(body[body.len - 1])),
                    "last statement must be a `return`",
                    .{},
                );
                return .{};
            }

            return .{};
        },
        .block => {
            try self.enterScope();
            for (self.ast.extractExtras(self.ast.nodeData(node_index).extra_range)) |i| {
                _ = try self.visitNode(@fromBackingInt(i));
            }
            self.leaveScope();
            return .{};
        },
        .if_full, .if_simple => {
            const info = Ast.info.ifAny(self.ast, node_index);

            _ = try self.visitNode(info.cond);

            try self.enterScope();
            _ = try self.visitNode(info.then_node);
            self.leaveScope();

            if (info.else_node.toIndex()) |else_node| {
                try self.enterScope();
                _ = try self.visitNode(else_node);
                self.leaveScope();
            }

            return .{};
        },
        .@"while" => {
            const cond, const body = self.ast.nodeData(node_index).node_node;

            _ = try self.visitNode(cond);

            self.inside_loop = true;
            try self.enterScope();

            _ = try self.visitNode(body);

            self.inside_loop = false;
            self.leaveScope();

            return .{};
        },
        .@"continue" => {
            if (!self.inside_loop) {
                try self.report(self.spanByNode(node_index), "`continue` outside of a loop", .{});
            }
            return .{};
        },
        .@"break" => {
            if (!self.inside_loop) {
                try self.report(self.spanByNode(node_index), "`break` outside of a loop", .{});
            }
            return .{};
        },
        .var_decl => {
            const info = Ast.info.varDecl(self.ast, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const gop_res = try self.vars.getOrPut(self.gpa, name);
            if (gop_res.found_existing) {
                if (gop_res.index < self.scope_tops.last() orelse 0) {
                    try self.report(
                        self.source.spanByToken(self.tokens.get(info.name_token)),
                        "declaration of `{s}` shadows name from outer scope",
                        .{name},
                    );
                } else {
                    try self.report(
                        self.source.spanByToken(self.tokens.get(info.name_token)),
                        "redeclaration of `{s}` in the same scope",
                        .{name},
                    );
                }
            } else {
                gop_res.value_ptr.* = .{
                    .mut = self.tokens.items(.kind)[info.mutability_token] == .kw_var,
                };
            }

            _ = try self.visitNode(self.ast.nodeData(node_index).node);

            return .{};
        },
        .name_ref => {
            const name_token = self.tokens.get(self.ast.nodeToken(node_index));
            const name = self.source.tokenLiteral(name_token);

            const var_opt = self.vars.get(name);
            if (var_opt) |v| {
                return .{ .is_assignable = v.mut };
            } else {
                try self.report(
                    self.source.spanByToken(name_token),
                    "reference to undefined variable `{s}`",
                    .{name},
                );
                return .{ .is_assignable = true };
            }
        },
        .bool_literal => return .{},
        .number => {
            const token = self.tokens.get(self.ast.nodeToken(node_index));

            const value = std.fmt.parseUnsigned(u64, self.source.tokenLiteral(token), 10) catch
                std.math.maxInt(u64); // greater than both |minInt(i64)| and maxInt(i64)

            if (value > std.math.maxInt(i64)) {
                try self.report(self.spanByNode(node_index), "integer literal out of range", .{});
            }

            return .{};
        },
        .@"return" => {
            _ = try self.visitNode(self.ast.nodeData(node_index).node);
            return .{};
        },
        .unary => {
            _ = try self.visitNode(self.ast.nodeData(node_index).node);
            return .{};
        },
        .binary => {
            const lhs, const rhs = self.ast.nodeData(node_index).node_node;
            _ = try self.visitNode(lhs);
            _ = try self.visitNode(rhs);
            return .{};
        },
        .assign => {
            const dest_index, const source_index = self.ast.nodeData(node_index).node_node;
            const dest_info = try self.visitNode(dest_index);
            if (!dest_info.is_assignable) {
                try self.report(self.spanByNode(dest_index), "expression is not assignable", .{});
            }

            _ = try self.visitNode(source_index);

            return .{};
        },
    }
}

fn spanByNode(self: *Self, node_index: Ast.Node.Index) Source.Span {
    return switch (self.ast.nodeKind(node_index)) {
        .root => .{ .begin = 0, .end = @intCast(self.source.text.len) },
        .var_decl => .{
            .begin = self.tokens.items(.offset)[self.ast.nodeToken(node_index)],
            .end = self.spanByNode(self.ast.nodeData(node_index).node).end,
        },
        .block => block: {
            const opening = self.tokens.items(.offset)[self.ast.nodeToken(node_index)];

            const data = self.ast.nodeData(node_index).extra_range;
            const body = self.ast.extractExtras(data);
            const last_stmt_end = if (body.len == 0)
                opening
            else
                self.spanByNode(@fromBackingInt(body[body.len - 1])).end;
            const end = std.mem.findScalarPos(u8, self.source.text, last_stmt_end, '}').?;

            break :block .{
                .begin = opening,
                .end = @intCast(end),
            };
        },
        .recovery,
        .name_ref,
        .bool_literal,
        .number,
        .@"continue",
        .@"break",
        => self.source.spanByToken(self.tokens.get(self.ast.nodeToken(node_index))),
        .@"while",
        .@"return",
        .unary,
        => .{
            .begin = self.tokens.items(.offset)[self.ast.nodeToken(node_index)],
            .end = self.spanByNode(self.ast.nodeData(node_index).node).end,
        },
        .if_full, .if_simple => if_span: {
            const info = Ast.info.ifAny(self.ast, node_index);
            const last_child = info.else_node.toIndex() orelse info.then_node;
            break :if_span .{
                .begin = self.tokens.items(.offset)[self.ast.nodeToken(node_index)],
                .end = self.spanByNode(last_child).end,
            };
        },
        .binary, .assign => bin: {
            const lhs, const rhs = self.ast.nodeData(node_index).node_node;
            break :bin .{
                .begin = self.spanByNode(lhs).begin,
                .end = self.spanByNode(rhs).end,
            };
        },
    };
}
