const Self = @This();

const std = @import("std");
const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/BitWriter.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
});

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
context: c.LLVMContextRef,
module: c.LLVMModuleRef,
builder: c.LLVMBuilderRef,
vars: std.StringHashMapUnmanaged(c.LLVMValueRef),

pub fn init(
    gpa: std.mem.Allocator,
    source: Source,
    tokens: lex.TokenList,
    ast: Ast,
) Self {
    const context = c.LLVMContextCreate();
    const module = c.LLVMModuleCreateWithName("spl");
    const builder = c.LLVMCreateBuilderInContext(context);

    return .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .ast = ast,
        .context = context,
        .module = module,
        .builder = builder,
        .vars = .empty,
    };
}

pub fn deinit(self: *Self) void {
    c.LLVMDisposeBuilder(self.builder);
    c.LLVMDisposeModule(self.module);
    c.LLVMContextDispose(self.context);
    self.vars.deinit(self.gpa);
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

fn i64Type(self: Self) c.LLVMTypeRef {
    return c.LLVMInt64TypeInContext(self.context);
}

fn gen(self: *Self, node_index: Ast.Node.Index) !c.LLVMValueRef {
    const node = self.ast.nodes.get(@intFromEnum(node_index));

    switch (node.kind) {
        .recovery => unreachable,
        .root => {
            const function_type: c.LLVMTypeRef = c.LLVMFunctionType(self.i64Type(), null, 0, 0);
            const function: c.LLVMValueRef = c.LLVMAddFunction(self.module, "main", function_type);
            const entry: c.LLVMBasicBlockRef = c.LLVMAppendBasicBlock(function, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);

            for (self.ast.extractExtras(node.data.extra_range)) |i| {
                _ = try self.gen(@enumFromInt(i));
            }

            return function;
        },
        .var_decl => {
            const name = self.source.tokenLiteral(self.tokens.get(node.token + 1));

            var null_terminated_name: [lex.Token.MAX_IDENT_LEN + 1]u8 = undefined;
            @memcpy(null_terminated_name[0..name.len], name);
            null_terminated_name[name.len] = 0;

            const alloca = c.LLVMBuildAlloca(self.builder, self.i64Type(), &null_terminated_name);
            try self.vars.put(self.gpa, name, alloca);

            const value = try self.gen(node.data.node);
            _ = c.LLVMBuildStore(self.builder, value, alloca);

            return alloca;
        },
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(node.token));
            const alloca = self.vars.get(name).?;
            return c.LLVMBuildLoad2(self.builder, self.i64Type(), alloca, "");
        },
        .number => {
            const literal = self.source.tokenLiteral(self.tokens.get(node.token));
            const value = std.fmt.parseUnsigned(u64, literal, 10) catch
                @panic("integer literals must be verified before codegen");
            return c.LLVMConstInt(self.i64Type(), value, @intFromBool(false));
        },
        .@"return" => {
            const value = try self.gen(node.data.node);
            return c.LLVMBuildRet(self.builder, value);
        },
        .unary => {
            const value = try self.gen(node.data.node);

            const token_kind = self.tokens.items(.kind)[node.token];
            switch (token_kind) {
                .minus => return c.LLVMBuildNeg(self.builder, value, ""),
                else => unreachable,
            }
        },
        .binary => {
            const lhs = try self.gen(node.data.node_node.@"0");
            const rhs = try self.gen(node.data.node_node.@"1");

            const token_kind = self.tokens.items(.kind)[node.token];
            switch (token_kind) {
                .plus => return c.LLVMBuildAdd(self.builder, lhs, rhs, ""),
                .minus => return c.LLVMBuildSub(self.builder, lhs, rhs, ""),
                .asterisk => return c.LLVMBuildMul(self.builder, lhs, rhs, ""),
                .slash => return c.LLVMBuildSDiv(self.builder, lhs, rhs, ""),
                else => unreachable,
            }
        },
        .assign => {
            const dest = self.genStorable(node.data.node_node.@"0");
            const src = try self.gen(node.data.node_node.@"1");
            return c.LLVMBuildStore(self.builder, src, dest);
        },
    }
}

fn genStorable(self: *Self, node_index: Ast.Node.Index) c.LLVMValueRef {
    const node = self.ast.nodes.get(@intFromEnum(node_index));

    // to be extended when structs and arrays are added
    switch (node.kind) {
        .name_ref => {
            const name = self.source.tokenLiteral(self.tokens.get(node.token));
            return self.vars.get(name).?;
        },
        .recovery,
        .root,
        .var_decl,
        .number,
        .@"return",
        .unary,
        .binary,
        .assign,
        => unreachable,
    }
}
