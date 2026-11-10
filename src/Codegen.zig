const Self = @This();

const std = @import("std");

const ir = @import("ir");

const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const lex = @import("lex.zig");

pub const Error = error{};

gpa: std.mem.Allocator,

context: *ir.Context,
builder: ir.Builder,

source: Source,
tokens: lex.TokenList.Slice,
ast: *const Ast,

function: ?ir.Function.Index,
declarations: std.StringHashMapUnmanaged(ir.Value.Index),
loop_stack: std.ArrayList(struct {
    header: ir.BasicBlock.Index,
    exit_block: ir.BasicBlock.Index,
}),

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList.Slice,
    ast: *const Ast,
    context: *ir.Context,
) Self {
    return .{
        .gpa = gpa,

        .context = context,
        .builder = .init(context),

        .source = source,
        .tokens = tokens,
        .ast = ast,

        .function = null,
        .declarations = .empty,
        .loop_stack = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.declarations.deinit(self.gpa);
    self.loop_stack.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    _ = try self.gen(.root);
}

const GenResult = struct {
    value: ?ir.Value.Index = null,
    is_terminator: bool = false,

    pub const terminator: GenResult = .{ .is_terminator = true };

    pub fn fromIndex(i: ir.Value.Index) GenResult {
        return .{ .value = i };
    }
};

fn gen(self: *Self, node_index: Ast.Node.Index) !GenResult {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => unreachable,
        .root => {
            const body: []const Ast.Node.Index =
                @ptrCast(self.ast.extractExtras(self.ast.nodeData(node_index).extra_range));

            for (body) |func| {
                const proto = switch (self.ast.nodeKind(func)) {
                    .fn_proto => func,
                    .fn_decl => self.ast.nodeData(func).node_and_node.@"0",
                    else => unreachable,
                };
                _ = try self.gen(proto);
            }

            for (body) |func| {
                if (self.ast.nodeKind(func) != .fn_decl) {
                    continue;
                }

                _ = try self.gen(func);
            }

            return .{};
        },
        .fn_proto => {
            const info = Ast.info.fnProto(self.ast.*, self.tokens, node_index);

            const param_types = try self.gpa.alloc(ir.Type.Handle, info.params.len);
            defer self.gpa.free(param_types);

            @memset(param_types, .primitive(.int64));

            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const fn_type = try self.context.createFunctionType(.primitive(.int64), param_types);
            const function_ref = try self.context.createFunction(name, fn_type);

            try self.declarations.put(self.gpa, name, function_ref.ref_index);

            return .{};
        },
        .fn_decl => {
            defer self.builder.detachFromFunction();

            const proto, const body = self.ast.nodeData(node_index).node_and_node;
            const proto_info = Ast.info.fnProto(self.ast.*, self.tokens, proto);

            const fn_name = self.source.tokenLiteral(self.tokens.get(proto_info.name_token));
            self.builder.positionAtFunction(@fromBackingInt(@intCast(self.context.functions.getIndex(fn_name).?)));

            const entry = try self.builder.createBasicBlock();
            self.builder.positionAtEnd(entry);

            for (proto_info.params) |param| {
                const bb_arg = try self.builder.createBlockArgument(.primitive(.int64));
                const alloca = try self.builder.createStackSlot(.primitive(.int64));
                _ = try self.builder.createStackStore(alloca, bb_arg);

                const name = self.source.tokenLiteral(self.tokens.get(param));
                try self.declarations.put(self.gpa, name, alloca);
            }

            _ = try self.gen(body);

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

            const info = Ast.info.ifAny(self.ast.*, node_index);
            const cond = (try self.gen(info.cond)).value.?;
            const header = self.builder.curBlock().?;

            self.builder.positionAtEnd(then_block);
            const then_info = try self.gen(info.then_node);

            var meet_block: ?ir.BasicBlock.Index = null;
            if (!then_info.is_terminator) {
                meet_block = try self.builder.createBasicBlock();
                _ = try self.builder.createJump(meet_block.?, &.{});
            }

            const else_block = if (info.else_node.toIndex()) |else_node| else_present: {
                const else_block = try self.builder.createBasicBlock();
                self.builder.positionAtEnd(else_block);
                const else_info = try self.gen(else_node);
                if (!else_info.is_terminator) {
                    if (meet_block == null) {
                        meet_block = try self.builder.createBasicBlock();
                    }
                    _ = try self.builder.createJump(meet_block.?, &.{});
                }
                break :else_present else_block;
            } else null;

            self.builder.positionAtEnd(header);
            _ = try self.builder.createBr(
                try self.builder.createCmp(
                    .ne,
                    cond,
                    try self.builder.newConstantInt(.primitive(.int64), 0),
                ),
                then_block,
                &.{},
                else_block orelse meet: {
                    if (meet_block == null) {
                        meet_block = try self.builder.createBasicBlock();
                    }
                    break :meet meet_block.?;
                },
                &.{},
            );

            if (meet_block) |meet| {
                self.builder.positionAtEnd(meet);
            }
            return .{};
        },
        .@"while" => {
            const cond_node, const body_node = self.ast.nodeData(node_index).node_and_node;

            const header = try self.builder.createBasicBlock();
            const body = try self.builder.createBasicBlock();
            const exit_block = try self.builder.createBasicBlock();

            // link current block to header
            _ = try self.builder.createJump(header, &.{});

            self.builder.positionAtEnd(header);
            const cond = (try self.gen(cond_node)).value.?;

            _ = try self.builder.createBr(
                try self.builder.createCmp(
                    .ne,
                    cond,
                    try self.builder.newConstantInt(.primitive(.int64), 0),
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

            self.builder.positionAtEnd(body);
            const body_info = try self.gen(body_node);
            if (!body_info.is_terminator) {
                _ = try self.builder.createJump(header, &.{});
            }

            _ = self.loop_stack.pop();

            self.builder.positionAtEnd(exit_block);
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
            const info = Ast.info.varDecl(self.ast.*, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const slot = try self.builder.createStackSlot(.primitive(.int64));
            try self.declarations.put(self.gpa, name, slot);

            const value = (try self.gen(info.init_expr)).value.?;
            _ = try self.builder.createStackStore(slot, value);

            return .{};
        },
        .call => {
            const info = Ast.info.call(self.ast.*, node_index);

            var args = try self.gpa.alloc(ir.Value.Index, info.args.len);
            defer self.gpa.free(args);

            for (info.args, 0..) |arg, i| {
                args[i] = (try self.gen(arg)).value.?;
            }

            const callee = (try self.gen(info.callee)).value.?;
            return .fromIndex(try self.builder.createCall(callee, args));
        },
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const declaration = self.declarations.get(name).?;

            return switch (self.context.values.items(.kind)[declaration.toInt()]) {
                .stack_slot => .fromIndex(try self.builder.createStackLoad(declaration)),
                .function_ref => .fromIndex(declaration),
                else => unreachable,
            };
        },
        .bool_literal => {
            const value = self.tokens.items(.kind)[self.ast.nodeToken(node_index)] == .kw_true;
            return .fromIndex(try self.builder.newConstantInt(.primitive(.int64), @intFromBool(value)));
        },
        .number => {
            const literal = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const value = std.fmt.parseUnsigned(u64, literal, 10) catch unreachable;
            return .fromIndex(try self.builder.newConstantInt(.primitive(.int64), value));
        },
        .@"return" => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value.?;
            _ = try self.builder.createRet(value);
            return .terminator;
        },
        .unary => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value.?;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .minus => return .fromIndex(try self.builder.createNegate(value)),
                .bang => {
                    const cmp = try self.builder.createCmp(
                        .eq,
                        value,
                        try self.builder.newConstantInt(.primitive(.int64), 0),
                    );

                    return .fromIndex(try self.builder.createZeroExtend(cmp, .primitive(.int64)));
                },
                else => unreachable,
            }
        },
        .binary => {
            const lhs_index, const rhs_index = self.ast.nodeData(node_index).node_and_node;
            const lhs = (try self.gen(lhs_index)).value.?;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .plus, .minus, .asterisk, .slash => {
                    const rhs = (try self.gen(rhs_index)).value.?;
                    return .fromIndex(try switch (token_kind) {
                        .plus => self.builder.createAdd(lhs, rhs),
                        .minus => self.builder.createSub(lhs, rhs),
                        .asterisk => self.builder.createMul(lhs, rhs),
                        .slash => self.builder.createDivSigned(lhs, rhs),
                        else => unreachable,
                    });
                },
                .eq, .ne, .lt, .gt, .le, .ge => {
                    const rhs = (try self.gen(rhs_index)).value.?;
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
                    return .fromIndex(try self.builder.createZeroExtend(cmp, .primitive(.int64)));
                },
                .logical_and, .logical_or => {
                    const rhs_block = try self.builder.createBasicBlock();
                    const next_block = try self.builder.createBasicBlock();

                    const false_lit = try self.builder.newConstantInt(.primitive(.int64), 0);
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
                            &.{try self.builder.newConstantInt(.primitive(.int64), 1)},
                            rhs_block,
                            &.{},
                        );
                    }

                    self.builder.positionAtEnd(rhs_block);
                    const rhs = (try self.gen(rhs_index)).value.?;
                    _ = try self.builder.createJump(next_block, &.{rhs});

                    self.builder.positionAtEnd(next_block);
                    const res = try self.builder.createBlockArgument(.primitive(.int64));
                    return .fromIndex(res);
                },
                else => unreachable,
            }
        },
        .assign => {
            const dest_index, const src_index = self.ast.nodeData(node_index).node_and_node;
            const dest = self.genStorable(dest_index);
            const src = (try self.gen(src_index)).value.?;

            // TODO: this will stop stop being a stack store one day
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
            return self.declarations.get(name).?;
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
        .fn_proto,
        .fn_decl,
        .call,
        => unreachable,
    }
}
