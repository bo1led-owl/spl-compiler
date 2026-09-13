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

pub fn visitNode(self: *Self, node_idx: Ast.Node.Index) (std.mem.Allocator.Error || ErrorBundle.ReportError)!void {
    const node = self.ast.nodes.get(@intFromEnum(node_idx));

    switch (node.kind) {
        .root => {
            const body = self.ast.extractExtras(node.data.extra_range);
            for (body) |i| {
                try self.visitNode(@enumFromInt(i));
            }
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

            try self.visitNode(node.data.node);
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
        },

        // TODO
        .number => {},
        .@"return" => {},
        .unary => {},
        .binary => {},
        .assign => {},
    }
}

fn report(self: *Self, span: Source.Span, comptime fmt: []const u8, args: anytype) ErrorBundle.ReportError!void {
    try self.errors.report(self.gpa, span, fmt, args);
}
