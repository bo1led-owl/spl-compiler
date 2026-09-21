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
    _ = try self.gen(.root);

    if (options.emit_llvm) {
        self.printModule(output_file);
    } else {
        self.makeBinaryFile(output_file);
    }
}

fn printModule(self: Self, output_file: [:0]const u8) void {
    var err_msg: [*:0]u8 = undefined;
    const failed = c.LLVMPrintModuleToFile(self.module, output_file, @ptrCast(&err_msg)) != 0;

    if (failed) {
        std.log.err("failed dumping LLVM IR: {s}", .{@as([*:0]u8, @ptrCast(&err_msg))});
        c.LLVMDisposeMessage(err_msg);
    }
}

fn makeBinaryFile(self: Self, output_file: [:0]const u8) void {
    _ = c.LLVMInitializeNativeTarget();
    _ = c.LLVMInitializeNativeAsmPrinter();

    const triple = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple);

    c.LLVMSetTarget(self.module, triple);

    var target: c.LLVMTargetRef = undefined;
    {
        var err_msg: [*:0]u8 = undefined;
        const failed = c.LLVMGetTargetFromTriple(triple, &target, @ptrCast(&err_msg)) != 0;
        if (failed) {
            std.log.err("failed to get target: {s}", .{err_msg});
            c.LLVMDisposeMessage(err_msg);
            return;
        }
    }

    const target_machine = c.LLVMCreateTargetMachine(
        target,
        triple,
        "generic",
        "",
        c.LLVMCodeGenLevelDefault,
        c.LLVMRelocDefault,
        c.LLVMCodeModelDefault,
    );
    defer c.LLVMDisposeTargetMachine(target_machine);

    {
        var err_msg: [*:0]u8 = undefined;
        const failed = c.LLVMTargetMachineEmitToFile(
            target_machine,
            self.module,
            output_file,
            c.LLVMObjectFile,
            @ptrCast(&err_msg),
        ) != 0;
        if (failed) {
            std.log.err("failed to emit object file: {s}", .{err_msg});
            c.LLVMDisposeMessage(err_msg);
            return;
        }
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
            const dest = try self.genStorable(node.data.node_node.@"0");
            const src = try self.gen(node.data.node_node.@"1");
            return c.LLVMBuildStore(self.builder, src, dest);
        },
    }
}

fn genStorable(self: *Self, node_index: Ast.Node.Index) !c.LLVMValueRef {
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
