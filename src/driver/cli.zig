const std = @import("std");

pub const help_msg =
    \\Usage: splc [options...] <filename>
    \\
    \\Arguments:
    \\  filename - path to the source file
    \\
    \\Options:
    \\  -h, --help                                   - print this message and exit
    \\  -o FILE, --output=FILE                       - set output file
    \\           --emit-llvm                         - output LLVM IR file and stop
    \\  -t DUMP, --tokens-dump=DUMP                  - dump tokens as JSON into DUMP
    \\  -a DUMP, --ast-dump=DUMP                     - dump AST as JSON into DUMP
    \\           --last-stage=<lexer|parser|codegen> - limit the compiler pipeline to specified stage
    \\           --preserve-temp                     - do not delete temporary files
++ "\n";

pub const Args = union(enum) {
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

    pub const Full = struct {
        source_path: []const u8,
        output_path: [:0]const u8,
        tokens_dump_path: ?[]const u8,
        ast_dump_path: ?[]const u8,
        last_stage: Stage,
        emit_llvm: bool,
        preserve_temp: bool,
    };

    help,
    full: Full,

    pub fn parse(args: std.process.Args) ParseError!Args {
        const Next = enum { tokens_dump, ast_dump, output };

        var source_path: ?[]const u8 = null;
        var output_path: ?[:0]const u8 = null;
        var tokens_dump_path: ?[]const u8 = null;
        var ast_dump_path: ?[]const u8 = null;
        var last_stage: Stage = .codegen;
        var emit_llvm = false;
        var preserve_temp = false;

        var next_opt: ?Next = null;

        const stages = std.StaticStringMap(Stage).initComptime(comptime init: {
            // iterate over all variants of the enum and make pairs like `("foo", .foo)`
            const fields = @typeInfo(Stage).@"enum".fields;
            var res: [fields.len]struct { []const u8, Stage } = undefined;
            for (fields, &res) |field, *res_item| {
                res_item.* = .{ field.name, @as(Stage, @enumFromInt(field.value)) };
            }
            break :init res;
        });

        var iter = args.iterate();
        _ = iter.next(); // skip program name

        while (iter.next()) |arg| {
            if (next_opt) |next| {
                next_opt = null;
                switch (next) {
                    .tokens_dump => tokens_dump_path = arg,
                    .ast_dump => ast_dump_path = arg,
                    .output => output_path = arg,
                }
            } else if (flag(arg, 'h', "help")) {
                return .help;
            } else if (flag(arg, 't', null)) {
                next_opt = .tokens_dump;
            } else if (longOption(arg, "tokens-dump")) |value| {
                tokens_dump_path = value;
            } else if (flag(arg, 'a', null)) {
                next_opt = .ast_dump;
            } else if (longOption(arg, "ast-dump")) |value| {
                ast_dump_path = value;
            } else if (flag(arg, 'o', null)) {
                next_opt = .output;
            } else if (longOption(arg, "output")) |value| {
                output_path = value;
            } else if (longOption(arg, "last-stage")) |value| {
                last_stage = stages.get(value) orelse return ParseError.UnknownStage;
            } else if (flag(arg, null, "emit-llvm")) {
                emit_llvm = true;
            } else if (flag(arg, null, "preserve-temp")) {
                preserve_temp = true;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return ParseError.UnknownOption;
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

        return .{ .full = .{
            .source_path = source_path.?,
            .tokens_dump_path = tokens_dump_path,
            .ast_dump_path = ast_dump_path,
            .emit_llvm = emit_llvm,
            .preserve_temp = preserve_temp,
            .last_stage = last_stage,
            .output_path = output_path orelse if (emit_llvm) "a.ll" else "a.out",
        } };
    }

    fn flag(arg: [:0]const u8, comptime short: ?u8, comptime long: ?[]const u8) bool {
        if (short) |s| {
            if (std.mem.eql(u8, arg, std.fmt.comptimePrint("-{c}", .{s}))) {
                return true;
            }
        }

        if (long) |l| {
            if (std.mem.eql(u8, arg, "--" ++ l)) {
                return true;
            }
        }

        return false;
    }

    fn longOption(arg: [:0]const u8, comptime name: []const u8) ?[:0]const u8 {
        const prefix = "--" ++ name ++ "=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            return arg[prefix.len..];
        }
        return null;
    }
};
