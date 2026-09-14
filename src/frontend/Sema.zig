const std = @import("std");

const Self = @This();

const lex = @import("lex.zig");
const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const ErrorBundle = @import("ErrorBundle.zig");

gpa: std.mem.Allocator,
source: Source,
tokens: lex.TokenList,
ast: Ast,
errors: *ErrorBundle,
vars: std.StringHashMapUnmanaged(struct { mut: bool }),

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
        .vars = .{},
    };
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

fn visitNode(self: *Self, node_idx: Ast.Node.Index) (std.mem.Allocator.Error || ErrorBundle.ReportError)!NodeInfo {
    const node = self.ast.nodes.get(@intFromEnum(node_idx));

    switch (node.kind) {
        .root => {
            const body = self.ast.extractExtras(node.data.extra_range);
            for (body) |i| {
                _ = try self.visitNode(@enumFromInt(i));
            }

            return .{};
        },
        .var_decl => {
            const name_token = self.tokens.get(node.token + 1);
            const name = self.source.tokenLiteral(name_token);

            const gop_res = try self.vars.getOrPut(self.gpa, name);
            if (gop_res.found_existing) {
                try self.report(
                    self.source.spanByToken(name_token),
                    "redeclaration of variable `{s}`",
                    .{name},
                );
            } else {
                gop_res.value_ptr.* = .{
                    .mut = self.tokens.items(.kind)[node.token] == .kw_var,
                };
            }

            _ = try self.visitNode(node.data.node);

            return .{};
        },
        .name_ref => {
            const name_token = self.tokens.get(node.token);
            const name = self.source.tokenLiteral(name_token);
            if (!self.vars.contains(name)) {
                try self.report(
                    self.source.spanByToken(name_token),
                    "reference to undefined variable `{s}`",
                    .{name},
                );
            }

            return .{ .is_assignable = true };
        },
        .number => {
            // TODO:
            // size check
            // how to handle negative literals?

            return .{};
        },
        .@"return" => {
            _ = try self.visitNode(node.data.node);
            return .{};
        },
        .unary => {
            _ = try self.visitNode(node.data.node);
            return .{};
        },
        .binary => {
            _ = try self.visitNode(node.data.node_node.@"0");
            _ = try self.visitNode(node.data.node_node.@"1");
            return .{};
        },
        .assign => {
            const dest_info = try self.visitNode(node.data.node_node.@"0");
            if (!dest_info.is_assignable) {
                try self.report(self.spanByNode(node_idx), "expression is not assignable", .{});
            }

            _ = try self.visitNode(node.data.node_node.@"1");

            return .{};
        },
    }
}

fn spanByNode(self: *Self, node_idx: Ast.Node.Index) Source.Span {
    const node = self.ast.nodes.get(@intFromEnum(node_idx));
    return switch (node.kind) {
        .root => .{ .begin = 0, .end = @intCast(self.source.text.len) },
        .var_decl => .{
            .begin = self.tokens.items(.offset)[node.token],
            .end = self.spanByNode(node.data.node).end,
        },
        .name_ref => self.source.spanByToken(self.tokens.get(node.token)),
        .number => self.source.spanByToken(self.tokens.get(node.token)),
        .@"return" => .{
            .begin = self.tokens.items(.offset)[node.token],
            .end = self.spanByNode(node.data.node).end,
        },
        .unary => .{
            .begin = self.tokens.items(.offset)[node.token],
            .end = self.spanByNode(node.data.node).end,
        },
        .binary => .{
            .begin = self.spanByNode(node.data.node_node.@"0").begin,
            .end = self.spanByNode(node.data.node_node.@"1").end,
        },
        .assign => .{
            .begin = self.spanByNode(node.data.node_node.@"0").begin,
            .end = self.spanByNode(node.data.node_node.@"1").end,
        },
    };
}
