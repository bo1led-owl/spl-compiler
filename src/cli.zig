const std = @import("std");

pub const help_msg =
    \\Usage: splc [options...] <filename>
    \\
    \\Arguments:
    \\  filename - path to the source file
    \\
    \\Options:
    \\  -h, --help                                   - print this message and exit
    \\  -o FILE, --output=FILE                       - output file
    \\           --emit-llvm                         - output LLVM IR file and stop
    \\  -t DUMP, --tokens-dump=DUMP                  - dump tokens as JSON into DUMP
    \\  -a DUMP, --ast-dump=DUMP                     - dump AST as JSON into DUMP
    \\           --last-stage=<lexer|parser|codegen> - limit the compiler pipeline to specified stage
++ "\n";

pub const Args = struct {
    pub const Stage = enum(u8) {
        lexer = 0,
        parser = 1,
        codegen = 2,
    };

    pub const ParseError = error{
        TooFewArguments,
        TooManyArguments,
        UnknownOption,
        MissingOptionValue,
        UnknownStage,
    };

    source_path: []const u8,
    output_path: [:0]const u8 = "",
    tokens_dump_path: ?[]const u8 = null,
    ast_dump_path: ?[]const u8 = null,
    last_stage: Stage = .codegen,
    emit_llvm: bool = false,
    help: bool = false,

    pub fn parse(args: std.process.Args) ParseError!Args {
        const Next = enum { tokens_dump, ast_dump, output };

        var source_path: ?[]const u8 = null;
        var output_path: ?[:0]const u8 = null;
        var tokens_dump_path: ?[]const u8 = null;
        var ast_dump_path: ?[]const u8 = null;
        var last_stage = Stage.codegen;
        var emit_llvm = false;

        var next_opt: ?Next = null;

        const stages = std.StaticStringMap(Stage).initComptime(comptime init: {
            // iterate over all variants of the enum and make pairs like `("foo", .foo)`
            var res: []const struct { []const u8, Stage } = &.{};
            for (@typeInfo(Stage).@"enum".fields) |field| {
                res = res ++ .{.{ field.name, @as(Stage, @enumFromInt(field.value)) }};
            }
            break :init res;
        });

        var iter = args.iterate();
        _ = iter.next(); // skip program name

        while (iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return .{ .help = true, .source_path = &.{} };
            } else if (std.mem.eql(u8, arg, "-t")) {
                next_opt = .tokens_dump;
            } else if (std.mem.startsWith(u8, arg, "--tokens-dump=")) {
                tokens_dump_path = arg[("--tokens-dump=".len)..];
            } else if (std.mem.eql(u8, arg, "-a")) {
                next_opt = .ast_dump;
            } else if (std.mem.startsWith(u8, arg, "--ast-dump=")) {
                ast_dump_path = arg[("--ast-dump=".len)..];
            } else if (std.mem.eql(u8, arg, "-o")) {
                next_opt = .output;
            } else if (std.mem.startsWith(u8, arg, "--output=")) {
                output_path = arg[("--output=".len)..];
            } else if (std.mem.startsWith(u8, arg, "--last-stage=")) {
                last_stage = stages.get(arg["--last-stage=".len..]) orelse
                    return ParseError.UnknownStage;
            } else if (std.mem.eql(u8, arg, "--emit-llvm")) {
                emit_llvm = true;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return ParseError.UnknownOption;
            } else if (next_opt) |next| {
                next_opt = null;
                switch (next) {
                    .tokens_dump => tokens_dump_path = arg,
                    .ast_dump => ast_dump_path = arg,
                    .output => output_path = arg,
                }
            } else if (source_path != null) {
                return ParseError.TooManyArguments;
            } else {
                source_path = arg;
            }
        }

        if (next_opt != null) {
            return ParseError.MissingOptionValue;
        }
        if (source_path == null) {
            return ParseError.TooFewArguments;
        }

        return .{
            .source_path = source_path.?,
            .tokens_dump_path = tokens_dump_path,
            .ast_dump_path = ast_dump_path,
            .emit_llvm = emit_llvm,
            .last_stage = last_stage,
            .output_path = if (emit_llvm) "a.ll" else "a.bc",
        };
    }
};
