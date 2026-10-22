const Self = @This();

const std = @import("std");

const backend = @import("backend");
const ir = backend.ir;

const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const lex = @import("lex.zig");

pub const Error = error{};

gpa: std.mem.Allocator,

context: *ir.Context,
builder: ir.Builder,

source: Source,
tokens: lex.TokenList,
ast: Ast,

slots: std.StringHashMapUnmanaged(ir.Value.Index),
loop_stack: std.ArrayList(struct {
    header: ir.BasicBlock.Index,
    exit_block: ir.BasicBlock.Index,
}),

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList,
    ast: Ast,
    context: *ir.Context,
) !Self {
    return .{
        .gpa = gpa,

        .context = context,
        .builder = try ir.Builder.initWithNewFunction(context, "main"),

        .source = source,
        .tokens = tokens,
        .ast = ast,

        .slots = .empty,
        .loop_stack = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.slots.deinit(self.gpa);
    self.loop_stack.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Self) !ir.Function {
    _ = try self.gen(.root);
    return self.context.functions.get("main").?;
}

const GenResult = struct {
    value: ir.Value.IndexOpt = .none,
    is_terminator: bool = false,

    pub const terminator: GenResult = .{ .is_terminator = true };

    pub fn fromIndex(i: ir.Value.Index) GenResult {
        return .{ .value = i.toIndexOpt() };
    }
};

fn gen(self: *Self, node_index: Ast.Node.Index) !GenResult {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => unreachable,
        .root => {
            for (self.ast.extractExtras(self.ast.nodeData(node_index).extra_range)) |i| {
                _ = try self.gen(@fromBackingInt(i));
            }

            return .{};
        },
        .block => {
            var seen_terminator = false;
            for (self.ast.extractExtras(self.ast.nodeData(node_index).extra_range)) |i| {
                const info = try self.gen(@fromBackingInt(i));
                seen_terminator |= info.is_terminator;
            }

            return .{ .is_terminator = seen_terminator };
        },
        .if_simple, .if_full => {
            const then_block = try self.builder.createBasicBlock();
            const meet_block = try self.builder.createBasicBlock();

            const info = Ast.info.ifAny(self.ast, node_index);
            const cond = (try self.gen(info.cond)).value.toIndex().?;
            const header = self.builder.block;

            self.builder.positionAtEnd(self.builder.function, then_block);
            const then_info = try self.gen(info.then_node);
            if (!then_info.is_terminator) {
                _ = try self.builder.createJump(meet_block, &.{});
            }

            const else_block = if (info.else_node.toIndex()) |else_node| else_present: {
                const else_block = try self.builder.createBasicBlock();
                self.builder.positionAtEnd(self.builder.function, else_block);
                const else_info = try self.gen(else_node);
                if (!else_info.is_terminator) {
                    _ = try self.builder.createJump(meet_block, &.{});
                }
                break :else_present else_block;
            } else null;

            self.builder.positionAtEnd(self.builder.function, header);
            _ = try self.builder.createBr(
                try self.builder.createCmp(
                    .ne,
                    cond,
                    try self.builder.newConstantInt(.{ .kind = .int64 }, 0),
                ),
                then_block,
                &.{},
                else_block orelse meet_block,
                &.{},
            );

            self.builder.positionAtEnd(self.builder.function, meet_block);
            return .{};
        },
        .@"while" => {
            const cond_node, const body_node = self.ast.nodeData(node_index).node_and_node;

            const header = try self.builder.createBasicBlock();
            const body = try self.builder.createBasicBlock();
            const exit_block = try self.builder.createBasicBlock();

            // link current block to header
            _ = try self.builder.createJump(header, &.{});

            self.builder.positionAtEnd(self.builder.function, header);
            const cond = (try self.gen(cond_node)).value.toIndex().?;

            _ = try self.builder.createBr(
                try self.builder.createCmp(
                    .ne,
                    cond,
                    try self.builder.newConstantInt(.{ .kind = .int64 }, 0),
                ),
                body,
                &.{},
                exit_block,
                &.{},
            );

            try self.loop_stack.append(self.gpa, .{
                .header = header,
                .exit_block = exit_block,
            });

            self.builder.positionAtEnd(self.builder.function, body);
            const body_info = try self.gen(body_node);
            if (!body_info.is_terminator) {
                _ = try self.builder.createJump(header, &.{});
            }

            _ = self.loop_stack.pop();

            self.builder.positionAtEnd(self.builder.function, exit_block);
            return .{};
        },
        .@"continue" => {
            const header = self.loop_stack.last().?.header;
            _ = try self.builder.createJump(header, &.{});
            return .terminator;
        },
        .@"break" => {
            const exit_block = self.loop_stack.last().?.exit_block;
            _ = try self.builder.createJump(exit_block, &.{});
            return .terminator;
        },
        .var_decl => {
            const info = Ast.info.varDecl(self.ast, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const slot = try self.builder.createStackSlot(.{ .kind = .int64 });
            try self.slots.put(self.gpa, name, slot);

            const value = (try self.gen(info.init_expr)).value.toIndex().?;
            _ = try self.builder.createStackStore(slot, value);

            return .{};
        },
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const slot = self.slots.get(name).?;
            return .fromIndex(try self.builder.createStackLoad(slot));
        },
        .bool_literal => {
            const value = self.tokens.items(.kind)[self.ast.nodeToken(node_index)] == .kw_true;
            return .fromIndex(try self.builder.newConstantInt(.{ .kind = .int64 }, @intFromBool(value)));
        },
        .number => {
            const literal = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const value = std.fmt.parseUnsigned(u64, literal, 10) catch unreachable;
            return .fromIndex(try self.builder.newConstantInt(.{ .kind = .int64 }, value));
        },
        .@"return" => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value.toIndex().?;
            _ = try self.builder.createRet(value);
            return .terminator;
        },
        .unary => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value.toIndex().?;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .minus => return .fromIndex(try self.builder.createNegate(value)),
                .bang => {
                    const cmp = try self.builder.createCmp(
                        .eq,
                        value,
                        try self.builder.newConstantInt(.{ .kind = .int64 }, 0),
                    );

                    return .fromIndex(try self.builder.createZeroExtend(cmp, .{ .kind = .int64 }));
                },
                else => unreachable,
            }
        },
        .binary => {
            const lhs_index, const rhs_index = self.ast.nodeData(node_index).node_and_node;
            const lhs = (try self.gen(lhs_index)).value.toIndex().?;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .plus, .minus, .asterisk, .slash => {
                    const rhs = (try self.gen(rhs_index)).value.toIndex().?;
                    return .fromIndex(try switch (token_kind) {
                        .plus => self.builder.createAdd(lhs, rhs),
                        .minus => self.builder.createSub(lhs, rhs),
                        .asterisk => self.builder.createMul(lhs, rhs),
                        .slash => self.builder.createDivSigned(lhs, rhs),
                        else => unreachable,
                    });
                },
                .eq, .ne, .lt, .gt, .le, .ge => {
                    const rhs = (try self.gen(rhs_index)).value.toIndex().?;
                    const pred: ir.Builder.CmpPredicate = switch (token_kind) {
                        .eq => .eq,
                        .ne => .ne,
                        .lt => .slt,
                        .le => .sle,
                        .gt => .sgt,
                        .ge => .sge,
                        else => unreachable,
                    };
                    const cmp = try self.builder.createCmp(pred, lhs, rhs);
                    return .fromIndex(try self.builder.createZeroExtend(cmp, .{ .kind = .int64 }));
                },
                .logical_and, .logical_or => {
                    const lhs_block = self.builder.block;

                    const rhs_block = try self.builder.createBasicBlock();
                    const next_block = try self.builder.createBasicBlock();

                    self.builder.positionAtEnd(self.builder.function, lhs_block);
                    const false_lit = try self.builder.newConstantInt(.{ .kind = .int64 }, 0);
                    if (token_kind == .logical_and) {
                        _ = try self.builder.createBr(
                            try self.builder.createCmp(.eq, lhs, false_lit),
                            next_block,
                            &.{false_lit},
                            rhs_block,
                            &.{},
                        );
                    } else {
                        _ = try self.builder.createBr(
                            try self.builder.createCmp(.ne, lhs, false_lit),
                            next_block,
                            &.{try self.builder.newConstantInt(.{ .kind = .int64 }, 1)},
                            rhs_block,
                            &.{},
                        );
                    }

                    self.builder.positionAtEnd(self.builder.function, rhs_block);
                    const rhs = (try self.gen(rhs_index)).value.toIndex().?;
                    _ = try self.builder.createJump(next_block, &.{rhs});

                    self.builder.positionAtEnd(self.builder.function, next_block);
                    const res = try self.builder.createBlockArgument(.{ .kind = .int64 });
                    return .fromIndex(res);
                },
                else => unreachable,
            }
        },
        .assign => {
            const dest_index, const src_index = self.ast.nodeData(node_index).node_and_node;
            const dest = self.genStorable(dest_index);
            const src = (try self.gen(src_index)).value.toIndex().?;

            // TODO: is this always `stackStore`?
            _ = try self.builder.createStackStore(dest, src);
            return .{};
        },
    }
}

fn genStorable(self: *Self, node_index: Ast.Node.Index) ir.Value.Index {
    // to be extended when structs and arrays are added
    switch (self.ast.nodeKind(node_index)) {
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            return self.slots.get(name).?;
        },
        .recovery,
        .root,
        .var_decl,
        .number,
        .@"return",
        .unary,
        .binary,
        .assign,
        .@"break",
        .@"continue",
        .@"while",
        .block,
        .bool_literal,
        .if_full,
        .if_simple,
        => unreachable,
    }
}
