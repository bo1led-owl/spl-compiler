const Self = @This();

const std = @import("std");
const c = @import("c");

const Source = @import("Source.zig");
const Ast = @import("Ast.zig");
const lex = @import("lex.zig");

pub const Options = struct {
    emit_llvm: bool = false,
};

pub const Error = error{
    FailedToGetTarget,
    FailedToEmitObjectFile,
    FailedToDumpIr,
};

gpa: std.mem.Allocator,

source: Source,
tokens: lex.TokenList,
ast: Ast,

i64Type: c.LLVMTypeRef,
context: c.LLVMContextRef,
module: c.LLVMModuleRef,
builder: c.LLVMBuilderRef,
function: c.LLVMValueRef,

allocas: std.StringHashMapUnmanaged(c.LLVMValueRef),
loop_stack: std.ArrayList(struct {
    header: c.LLVMBasicBlockRef,
    exit_block: c.LLVMBasicBlockRef,
}),

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList,
    ast: Ast,
) Self {
    const context = c.LLVMContextCreate();
    const module = c.LLVMModuleCreateWithName("spl"); // "spl" may be replaced with actual filename
    const builder = c.LLVMCreateBuilderInContext(context);
    const i64Type = c.LLVMInt64TypeInContext(context);

    return .{
        .gpa = gpa,

        .source = source,
        .tokens = tokens,
        .ast = ast,

        .i64Type = i64Type,
        .context = context,
        .module = module,
        .builder = builder,
        .function = c.LLVMAddFunction(module, "main", c.LLVMFunctionType(i64Type, null, 0, 0)),

        .allocas = .empty,
        .loop_stack = .empty,
    };
}

pub fn deinit(self: *Self) void {
    c.LLVMDisposeBuilder(self.builder);
    c.LLVMDisposeModule(self.module);
    c.LLVMContextDispose(self.context);
    self.allocas.deinit(self.gpa);
    self.loop_stack.deinit(self.gpa);
    self.* = undefined;
}

pub fn run(self: *Self, output_file: [:0]const u8, options: Options) !void {
    _ = c.LLVMInitializeX86TargetInfo();
    _ = c.LLVMInitializeX86Target();
    _ = c.LLVMInitializeX86TargetMC();
    _ = c.LLVMInitializeX86AsmPrinter();

    const triple = "x86_64-unknown-linux-gnu";
    c.LLVMSetTarget(self.module, triple);

    var target: c.LLVMTargetRef = undefined;
    try checkLlvmBool(
        c.LLVMGetTargetFromTriple,
        .{ triple, &target },
        Error.FailedToGetTarget,
    );

    const target_machine = c.LLVMCreateTargetMachine(
        target,
        triple,
        "x86-64",
        "",
        c.LLVMCodeGenLevelDefault,
        c.LLVMRelocDefault,
        c.LLVMCodeModelDefault,
    );
    defer c.LLVMDisposeTargetMachine(target_machine);

    const data_layout = c.LLVMCreateTargetDataLayout(target_machine);
    c.LLVMSetModuleDataLayout(self.module, data_layout);

    _ = try self.gen(.root);

    if (options.emit_llvm) {
        try checkLlvmBool(
            c.LLVMPrintModuleToFile,
            .{ self.module, output_file },
            Error.FailedToDumpIr,
        );
    } else {
        try checkLlvmBool(
            c.LLVMTargetMachineEmitToFile,
            .{ target_machine, self.module, output_file, c.LLVMObjectFile },
            Error.FailedToEmitObjectFile,
        );
    }
}

fn checkLlvmBool(comptime function: anytype, args: anytype, err: anyerror) !void {
    var err_msg: [*c]u8 = undefined;
    const result: c.LLVMBool = @call(.auto, function, args ++ .{&err_msg});
    if (result != 0) {
        std.log.warn("LLVM error message: {s}", .{err_msg});
        c.LLVMDisposeMessage(@ptrCast(err_msg));
        return err;
    }
}

fn getCurrentBlock(self: Self) c.LLVMBasicBlockRef {
    return c.LLVMGetInsertBlock(self.builder);
}

fn newBasicBlock(self: *Self, name: [*:0]const u8) c.LLVMBasicBlockRef {
    return c.LLVMAppendBasicBlock(self.function, name);
}

fn positionBuilderAtEnd(self: *Self, bb: c.LLVMBasicBlockRef) void {
    c.LLVMPositionBuilderAtEnd(self.builder, bb);
}

const GenResult = struct {
    value: c.LLVMValueRef = null,
    is_terminator: bool = false,

    pub const terminator: GenResult = .{ .is_terminator = true };
};

fn gen(self: *Self, node_index: Ast.Node.Index) !GenResult {
    switch (self.ast.nodeKind(node_index)) {
        .recovery => unreachable,
        .root => {
            const entry = self.newBasicBlock("entry");
            self.positionBuilderAtEnd(entry);

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
            const then_block = self.newBasicBlock("");
            const meet_block = self.newBasicBlock("");

            const info = Ast.info.ifAny(self.ast, node_index);
            const cond = (try self.gen(info.cond)).value;
            const header = self.getCurrentBlock();

            self.positionBuilderAtEnd(then_block);
            const then_info = try self.gen(info.then_node);
            if (!then_info.is_terminator) {
                _ = c.LLVMBuildBr(self.builder, meet_block);
            }

            const else_block = if (info.else_node.toIndex()) |else_node| else_present: {
                const else_block = self.newBasicBlock("");
                self.positionBuilderAtEnd(else_block);
                const else_info = try self.gen(else_node);
                if (!else_info.is_terminator) {
                    _ = c.LLVMBuildBr(self.builder, meet_block);
                }
                break :else_present else_block;
            } else null;

            self.positionBuilderAtEnd(header);
            _ = c.LLVMBuildCondBr(
                self.builder,
                c.LLVMBuildICmp(
                    self.builder,
                    c.LLVMIntNE,
                    cond,
                    c.LLVMConstInt(self.i64Type, 0, @intFromBool(false)),
                    "",
                ),
                then_block,
                else_block orelse meet_block,
            );

            self.positionBuilderAtEnd(meet_block);
            return .{};
        },
        .@"while" => {
            const cond_node, const body_node = self.ast.nodeData(node_index).node_and_node;

            const header = self.newBasicBlock("");
            const body = self.newBasicBlock("");
            const exit_block = self.newBasicBlock("");

            // link current block to header
            _ = c.LLVMBuildBr(self.builder, header);

            self.positionBuilderAtEnd(header);
            const cond = (try self.gen(cond_node)).value;
            _ = c.LLVMBuildCondBr(
                self.builder,
                c.LLVMBuildICmp(
                    self.builder,
                    c.LLVMIntNE,
                    cond,
                    c.LLVMConstInt(self.i64Type, 0, @intFromBool(false)),
                    "",
                ),
                body,
                exit_block,
            );

            try self.loop_stack.append(self.gpa, .{
                .header = header,
                .exit_block = exit_block,
            });

            self.positionBuilderAtEnd(body);
            const body_info = try self.gen(body_node);
            if (!body_info.is_terminator) {
                _ = c.LLVMBuildBr(self.builder, header);
            }

            _ = self.loop_stack.pop();

            self.positionBuilderAtEnd(exit_block);
            return .{};
        },
        .@"continue" => {
            const header = self.loop_stack.last().?.header;
            _ = c.LLVMBuildBr(self.builder, header);
            return .terminator;
        },
        .@"break" => {
            const exit_block = self.loop_stack.last().?.exit_block;
            _ = c.LLVMBuildBr(self.builder, exit_block);
            return .terminator;
        },
        .var_decl => {
            const info = Ast.info.varDecl(self.ast, node_index);
            const name = self.source.tokenLiteral(self.tokens.get(info.name_token));

            const alloca = c.LLVMBuildAlloca(self.builder, self.i64Type, "");
            try self.allocas.put(self.gpa, name, alloca);

            const value = (try self.gen(info.init_expr)).value;
            _ = c.LLVMBuildStore(self.builder, value, alloca);

            return .{};
        },
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const alloca = self.allocas.get(name).?;
            return .{ .value = c.LLVMBuildLoad2(self.builder, self.i64Type, alloca, "") };
        },
        .bool_literal => {
            const value = self.tokens.items(.kind)[self.ast.nodeToken(node_index)] == .kw_true;
            return .{ .value = c.LLVMConstInt(self.i64Type, @intFromBool(value), @intFromBool(false)) };
        },
        .number => {
            const literal = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            const value = std.fmt.parseUnsigned(u64, literal, 10) catch unreachable;
            return .{ .value = c.LLVMConstInt(self.i64Type, value, @intFromBool(false)) };
        },
        .@"return" => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value;
            _ = c.LLVMBuildRet(self.builder, value);
            return .terminator;
        },
        .unary => {
            const value = (try self.gen(self.ast.nodeData(node_index).node)).value;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .minus => return .{ .value = c.LLVMBuildNeg(self.builder, value, "") },
                .bang => {
                    const cmp = c.LLVMBuildICmp(
                        self.builder,
                        c.LLVMIntEQ,
                        value,
                        c.LLVMConstInt(self.i64Type, 0, @intFromBool(false)),
                        "",
                    );
                    return .{ .value = c.LLVMBuildZExt(self.builder, cmp, self.i64Type, "") };
                },
                else => unreachable,
            }
        },
        .binary => {
            const lhs_index, const rhs_index = self.ast.nodeData(node_index).node_and_node;
            const lhs = (try self.gen(lhs_index)).value;

            const token_kind = self.tokens.items(.kind)[self.ast.nodeToken(node_index)];
            switch (token_kind) {
                .plus, .minus, .asterisk, .slash => {
                    const rhs = (try self.gen(rhs_index)).value;
                    return .{ .value = switch (token_kind) {
                        .plus => c.LLVMBuildAdd(self.builder, lhs, rhs, ""),
                        .minus => c.LLVMBuildSub(self.builder, lhs, rhs, ""),
                        .asterisk => c.LLVMBuildMul(self.builder, lhs, rhs, ""),
                        .slash => c.LLVMBuildSDiv(self.builder, lhs, rhs, ""),
                        else => unreachable,
                    } };
                },
                .eq, .ne, .lt, .gt, .le, .ge => {
                    const rhs = (try self.gen(rhs_index)).value;
                    const pred: c.LLVMIntPredicate = switch (token_kind) {
                        .eq => c.LLVMIntEQ,
                        .ne => c.LLVMIntNE,
                        .lt => c.LLVMIntSLT,
                        .le => c.LLVMIntSLE,
                        .gt => c.LLVMIntSGT,
                        .ge => c.LLVMIntSGE,
                        else => unreachable,
                    };
                    const cmp = c.LLVMBuildICmp(self.builder, pred, lhs, rhs, "");
                    return .{ .value = c.LLVMBuildZExt(self.builder, cmp, self.i64Type, "") };
                },
                .logical_and, .logical_or => {
                    const lhs_block = self.getCurrentBlock();

                    const rhs_block = self.newBasicBlock("");
                    const next_block = self.newBasicBlock("");

                    _ = c.LLVMBuildCondBr(
                        self.builder,
                        c.LLVMBuildICmp(
                            self.builder,
                            if (token_kind == .logical_and) c.LLVMIntEQ else c.LLVMIntNE,
                            lhs,
                            c.LLVMConstInt(self.i64Type, 0, @intFromBool(false)),
                            "",
                        ),
                        next_block,
                        rhs_block,
                    );

                    self.positionBuilderAtEnd(rhs_block);
                    const rhs = (try self.gen(rhs_index)).value;
                    _ = c.LLVMBuildBr(self.builder, next_block);

                    self.positionBuilderAtEnd(next_block);
                    const res = c.LLVMBuildPhi(self.builder, self.i64Type, "");

                    var incoming_values: [2]c.LLVMValueRef = .{
                        c.LLVMConstInt(
                            self.i64Type,
                            @intFromBool(token_kind == .logical_or),
                            @intFromBool(false),
                        ),
                        rhs,
                    };
                    var incoming_blocks: [2]c.LLVMBasicBlockRef = .{ lhs_block, rhs_block };
                    c.LLVMAddIncoming(res, @ptrCast(&incoming_values), @ptrCast(&incoming_blocks), 2);

                    return .{ .value = res };
                },
                else => unreachable,
            }
        },
        .assign => {
            const dest_index, const src_index = self.ast.nodeData(node_index).node_and_node;
            const dest = self.genStorable(dest_index);
            const src = (try self.gen(src_index)).value;
            _ = c.LLVMBuildStore(self.builder, src, dest);
            return .{};
        },
    }
}

fn genStorable(self: *Self, node_index: Ast.Node.Index) c.LLVMValueRef {
    // to be extended when structs and arrays are added
    switch (self.ast.nodeKind(node_index)) {
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(self.ast.nodeToken(node_index)));
            return self.allocas.get(name).?;
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
