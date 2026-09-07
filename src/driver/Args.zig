const std = @import("std");

pub const ParseError = error{
    TooFewArguments,
    TooManyArguments,
    UnknownOption,
    MissingOptionValue,
};

path: []const u8,
tokens_dump_path: ?[]const u8 = null,
ast_dump_path: ?[]const u8 = null,
help: bool = false,

pub fn parse(args: std.process.Args) ParseError!@This() {
    const Next = enum { tokens_dump, ast_dump };

    var path: ?[]const u8 = null;
    var tokens_dump_path: ?[]const u8 = null;
    var ast_dump_path: ?[]const u8 = null;

    var next_opt: ?Next = null;

    var iter = args.iterate();
    _ = iter.next(); // skip program name

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .help = true, .path = &.{} };
        } else if (std.mem.eql(u8, arg, "-t")) {
            next_opt = .tokens_dump;
        } else if (std.mem.startsWith(u8, arg, "--tokens-dump=")) {
            tokens_dump_path = arg[("--tokens-dump=".len)..];
        } else if (std.mem.eql(u8, arg, "-a")) {
            next_opt = .ast_dump;
        } else if (std.mem.startsWith(u8, arg, "--ast-dump=")) {
            ast_dump_path = arg[("--ast-dump=".len)..];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return ParseError.UnknownOption;
        } else if (next_opt) |next| {
            next_opt = null;
            switch (next) {
                .tokens_dump => tokens_dump_path = arg,
                .ast_dump => ast_dump_path = arg,
            }
        } else if (path != null) {
            return ParseError.TooManyArguments;
        } else {
            path = arg;
        }
    }

    if (next_opt != null) {
        return ParseError.MissingOptionValue;
    }
    if (path == null) {
        return ParseError.TooFewArguments;
    }

    return .{
        .path = path.?,
        .tokens_dump_path = tokens_dump_path,
        .ast_dump_path = ast_dump_path,
    };
}
