const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const interface_mod = b.addModule("interface.zig", .{
        .source_file = .{ .path = "src/interface.zig" },
    });

    const exe = b.addTest(.{
        .root_source_file = .{ .path = "src/examples.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("interface", interface_mod);

    b.getInstallStep().dependOn(&b.addRunArtifact(exe).step);
}
