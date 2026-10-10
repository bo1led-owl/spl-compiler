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

/// Defined named entities
names: std.StringArrayHashMapUnmanaged(struct { declaration: Ast.Node.Index }),
/// Because `vars` is an `ArrayHashMap`, we can use indices to keep track of scope stacking
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

fn reportSimpleError(self: *Self, span: Source.Span, comptime fmt: []const u8, args: anytype) ErrorBundle.ReportError!void {
    try self.errors.addMessage(span, fmt, args);
    try self.errors.finishReport();
}

fn enterScope(self: *Self) !void {
    try self.scope_tops.append(self.gpa, @intCast(self.names.entries.len));
}

fn leaveScope(self: *Self) void {
    const top = self.scope_tops.pop().?;
    self.names.shrinkRetainingCapacity(@intCast(top));
}

comptime {
    // make `NodeInfo` packed if this fails
    std.debug.assert(@sizeOf(NodeInfo) <= 8);
}

const NodeInfo = enum {
    none,
    assignable,
    valid_lvalue_but_constant,
    terminator,
};

fn visitNode(self: *Self, node_index: Ast.Node.Index) ErrorBundle.ReportError!NodeInfo {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => return .assignable,

        // TODO: split this when implementing grammar 3
        .root, .block => |kind| {
            const body = self.ast.extractExtras(self.ast.nodeData(node_index).extra_range);

            if (kind == .root) {
                if (body.len == 0) {
                    try self.reportSimpleError(
                        self.spanByNode(node_index),
                        "empty program, at least one statement expected",
                        .{},
                    );
                    return .none;
                }
            }

            if (kind == .block) {
                try self.enterScope();
            }
            defer if (kind == .block) self.leaveScope();

            var terminator: ?Ast.Node.Index = null;
            for (body) |i| {
                if (terminator) |terminator_index| {
                    try self.errors.addMessage(self.spanByNode(@fromBackingInt(i)), "unreachable code", .{});
                    try self.errors.addMessage(self.spanByNode(terminator_index), "control flow was diverted here", .{});
                    try self.errors.finishReport();
                }

                const info = try self.visitNode(@fromBackingInt(i));
                if (terminator == null and info == .terminator) {
                    terminator = @fromBackingInt(i);
                }
            }

            if (kind == .root) {
                const last_node = self.ast.nodes.get(body[body.len - 1]);
                if (last_node.kind != .@"return") {
                    try self.reportSimpleError(
                        self.spanByNode(@fromBackingInt(body[body.len - 1])),
                        "last statement must be a `return`",
                        .{},
                    );
                }
                return .none;
            } else {
                return if (terminator != null) .terminator else .none;
            }
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

            return .none;
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
                try self.reportSimpleError(self.spanByNode(node_index), "`continue` outside of a loop", .{});
            }
            return .terminator;
        },
        .@"break" => {
            if (!self.inside_loop) {
                try self.reportSimpleError(self.spanByNode(node_index), "`break` outside of a loop", .{});
            }
            return .terminator;
        },
        .var_decl => {
            const info = Ast.info.varDecl(self.ast, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const gop_res = try self.names.getOrPut(self.gpa, name);
            if (gop_res.found_existing) {
                const prev_declaration_node_index = gop_res.value_ptr.declaration;

                const prev_declaration_kind: []const u8 =
                    switch (self.ast.nodeKind(prev_declaration_node_index)) {
                        .var_decl => var_decl: {
                            const mutability_token =
                                self.tokens.items(.kind)[self.ast.nodeToken(prev_declaration_node_index)];
                            const is_mutable = mutability_token == .kw_var;
                            break :var_decl if (is_mutable) "variable" else "constant";
                        },
                        else => unreachable, // TODO: extend when more entity kinds are added
                    };

                const defined_in_current_scope = gop_res.index >= self.scope_tops.last() orelse 0;
                if (defined_in_current_scope) {
                    try self.errors.addMessage(
                        self.source.spanByToken(self.tokens.get(info.name_token)),
                        "redeclaration of {s} `{s}` in the same scope",
                        .{ prev_declaration_kind, name },
                    );
                } else {
                    try self.errors.addMessage(
                        self.source.spanByToken(self.tokens.get(info.name_token)),
                        "declaration of `{s}` shadows {s} from outer scope",
                        .{ name, prev_declaration_kind },
                    );
                }
                try self.errors.addMessage(self.spanByNode(prev_declaration_node_index), "previously declared here", .{});
                try self.errors.finishReport();
            } else {
                gop_res.value_ptr.* = .{ .declaration = node_index };
            }

            _ = try self.visitNode(self.ast.nodeData(node_index).node);

            return .none;
        },
        .name_ref => {
            const name_token = self.tokens.get(self.ast.nodeToken(node_index));
            const name = self.source.tokenLiteral(name_token);

            const entity_opt = self.names.get(name);
            if (entity_opt) |entity| {
                switch (self.ast.nodeKind(entity.declaration)) {
                    .var_decl => {
                        const mutability_token = self.tokens.items(.kind)[self.ast.nodeToken(entity.declaration)];
                        const is_mutable = mutability_token == .kw_var;
                        if (is_mutable) {
                            return .assignable;
                        }
                        return .valid_lvalue_but_constant;
                    },
                    else => unreachable, // TODO: extend when more entity kinds are added
                }
            } else {
                try self.reportSimpleError(
                    self.source.spanByToken(name_token),
                    "reference to undefined name `{s}`",
                    .{name},
                );
                return .assignable;
            }
        },
        .bool_literal => return .none,
        .number => {
            const token = self.tokens.get(self.ast.nodeToken(node_index));

            const value = std.fmt.parseUnsigned(u64, self.source.tokenLiteral(token), 10) catch
                std.math.maxInt(u64); // greater than both |minInt(i64)| and maxInt(i64)

            if (value > std.math.maxInt(i64)) {
                try self.reportSimpleError(
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
            return .terminator;
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
            switch (dest_info) {
                .assignable => {},
                .valid_lvalue_but_constant => {
                    const declaration_node = switch (self.ast.nodeKind(dest_index)) {
                        .name_ref => name_ref: {
                            const name_token = self.tokens.get(self.ast.nodeToken(dest_index));
                            break :name_ref self.names.get(self.source.tokenLiteral(name_token)).?.declaration;
                        },
                        else => unreachable,
                    };

                    try self.errors.addMessage(
                        self.spanByNode(dest_index),
                        "cannot assign to constant",
                        .{},
                    );
                    try self.errors.addMessage(
                        self.spanByNode(declaration_node),
                        "declared as constant here",
                        .{},
                    );
                    try self.errors.finishReport();
                },
                .none, .terminator => try self.reportSimpleError(
                    self.spanByNode(dest_index),
                    "expression is not assignable",
                    .{},
                ),
            }

            _ = try self.visitNode(source_index);

            return .none;
        },
    }
}

fn spanByNode(self: *Self, node_index: Ast.Node.Index) Source.Span {
    return switch (self.ast.nodeKind(node_index)) {
        .root => unreachable,
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
        .@"return",
        .unary,
        => .{
            .begin = self.tokens.items(.offset)[self.ast.nodeToken(node_index)],
            .end = self.spanByNode(self.ast.nodeData(node_index).node).end,
        },
        .@"while" => .{
            .begin = self.tokens.items(.offset)[self.ast.nodeToken(node_index)],
            .end = self.spanByNode(self.ast.nodeData(node_index).node_and_node.@"1").end,
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
            const lhs, const rhs = self.ast.nodeData(node_index).node_and_node;
            break :bin .{
                .begin = self.spanByNode(lhs).begin,
                .end = self.spanByNode(rhs).end,
            };
        },
    };
}
