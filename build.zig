const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("interface.zig", .{
        .source_file = .{ .path = "interface.zig" },
    });
}
