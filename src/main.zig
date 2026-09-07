const std = @import("std");
const Io = std.Io;

const spl = @import("spl");

var stdout_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

pub fn main(init: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;

    var io_impl = std.Io.Threaded.init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer io_impl.deinit();

    const io = io_impl.io();

    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);

    try stdout_writer.interface.print("Hello spl!\n", .{});
    try stdout_writer.flush();
}
