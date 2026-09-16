pub const cli = @import("cli.zig");
pub const frontend = @import("frontend.zig");
pub const Codegen = @import("Codegen.zig");

test {
    _ = cli;
    _ = frontend;
    _ = Codegen;
}
