const interface = @import("interface.zig");
const Interface = interface.Interface;
const SelfType = interface.SelfType;

const std = @import("std");
const mem = std.mem;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;

test "Allocator interface example" {
    const Allocator = struct {
        const Self = @This();
        pub const Error = error{OutOfMemory};

        const IFace = Interface(struct {
            reallocFn: fn (*SelfType, []u8, u29, usize, u29) Error![]u8,
            shrinkFn: fn (*SelfType, []u8, u29, usize, u29) []u8,
        }, interface.Storage.NonOwning);

        iface: IFace,

        pub fn init(impl_ptr: var) Self {
            return .{
                .iface = try IFace.init(.{impl_ptr}),
            };
        }

        pub fn create(self: *Self, comptime T: type) Error!*T {
            if (@sizeOf(T) == 0) return &(T{});
            const slice = try self.alloc(T, 1);
            return &slice[0];
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) Error![]T {
            return self.alignedAlloc(T, null, n);
        }

        pub fn alignedAlloc(self: *Self, comptime T: type, comptime alignment: ?u29, n: usize) Error![]align(alignment orelse @alignOf(T)) T {
            const a = if (alignment) |a| blk: {
                if (a == @alignOf(T)) return alignedAlloc(self, T, null, n);
                break :blk a;
            } else @alignOf(T);

            if (n == 0) {
                return @as([*]align(a) T, undefined)[0..0];
            }

            const byte_count = std.math.mul(usize, @sizeOf(T), n) catch return Error.OutOfMemory;
            const byte_slice = try self.iface.call("reallocFn", .{ &[0]u8{}, undefined, byte_count, a });

            assert(byte_slice.len == byte_count);
            @memset(byte_slice.ptr, undefined, byte_slice.len);
            if (alignment == null) {
                return @intToPtr([*]T, @ptrToInt(byte_slice.ptr))[0..n];
            } else {
                return mem.bytesAsSlice(T, @alignCast(a, byte_slice));
            }
        }

        pub fn destroy(self: *Self, ptr: var) void {
            const T = @TypeOf(ptr).Child;
            if (@sizeOf(T) == 0) return;
            const non_const_ptr = @intToPtr([*]u8, @ptrToInt(ptr));
            const shrink_result = self.iface.call("shrinkFn", .{ non_const_ptr[0..@sizeOf(T)], @alignOf(T), 0, 1 });
            assert(shrink_result.len == 0);
        }

        // ETC...
    };

    // Allocator-compatible wrapper for *mem.Allocator
    const WrappingAllocator = struct {
        const Self = @This();

        allocator: *mem.Allocator,

        pub fn init(allocator: *mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        // Implement Allocator interface.
        pub fn reallocFn(self: Self, old_mem: []u8, old_alignment: u29, new_byte_count: usize, new_alignment: u29) ![]u8 {
            return self.allocator.reallocFn(self.allocator, old_mem, old_alignment, new_byte_count, new_alignment);
        }

        pub fn shrinkFn(self: Self, old_mem: []u8, old_alignment: u29, new_byte_count: usize, new_alignment: u29) []u8 {
            return self.allocator.shrinkFn(self.allocator, old_mem, old_alignment, new_byte_count, new_alignment);
        }
    };

    var wrapping_alloc = WrappingAllocator.init(std.testing.allocator);
    var alloc = Allocator.init(&wrapping_alloc);

    const some_mem = try alloc.create(u64);
    defer alloc.destroy(some_mem);
}

test "Simple NonOwning interface" {
    const NonOwningTest = struct {
        fn run() !void {
            const Fooer = Interface(struct {
                foo: fn (*SelfType) usize,
            }, interface.Storage.NonOwning);

            const TestFooer = struct {
                const Self = @This();

                state: usize,

                fn foo(self: *Self) usize {
                    const tmp = self.state;
                    self.state += 1;
                    return tmp;
                }
            };

            var f = TestFooer{ .state = 42 };
            var fooer = try Fooer.init(.{&f});
            defer fooer.deinit();

            expectEqual(@as(usize, 42), fooer.call("foo", .{}));
            expectEqual(@as(usize, 43), fooer.call("foo", .{}));
        }
    };

    try NonOwningTest.run();
    comptime try NonOwningTest.run();
}

test "Comptime only interface" {
    const TestIFace = Interface(struct {
        foo: fn (*SelfType, u8) u8,
    }, interface.Storage.Comptime);

    const TestType = struct {
        const Self = @This();

        state: u8,

        fn foo(self: Self, a: u8) u8 {
            return self.state + a;
        }
    };

    comptime var iface = try TestIFace.init(.{TestType{ .state = 0 }});
    expectEqual(@as(u8, 42), iface.call("foo", .{42}));
}

test "Owning interface with optional function" {
    const OwningOptionalFuncTest = struct {
        fn run() !void {
            const TestOwningIface = Interface(struct {
                someFn: ?fn (*const SelfType, usize, usize) usize,
                otherFn: fn (*SelfType, usize) anyerror!void,
            }, interface.Storage.Owning);

            const TestStruct = struct {
                const Self = @This();

                state: usize,

                fn someFn(self: Self, a: usize, b: usize) usize {
                    return self.state * a + b;
                }

                // Note that our return type need only coerce to the virtual function's
                // return type.
                fn otherFn(self: *Self, new_state: usize) void {
                    self.state = new_state;
                }
            };

            var iface_instance = try TestOwningIface.init(.{ comptime TestStruct{ .state = 0 }, std.testing.allocator });
            defer iface_instance.deinit();

            try iface_instance.call("otherFn", .{100});
            expectEqual(@as(usize, 42), iface_instance.call("someFn", .{ 0, 42 }).?);
        }
    };

    try OwningOptionalFuncTest.run();
}

test "Interface with virtual async function implemented by an async function" {
    const AsyncIFace = Interface(struct {
        const async_call_stack_size = 1024;

        foo: async fn (*SelfType) void,
    }, interface.Storage.NonOwning);

    const Impl = struct {
        const Self = @This();

        state: usize,
        frame: anyframe = undefined,

        fn foo(self: *Self) void {
            suspend {
                self.frame = @frame();
            }
            self.state += 1;
            suspend;
            self.state += 1;
        }
    };

    var i = Impl{ .state = 0 };
    var instance = try AsyncIFace.init(.{&i});
    _ = async instance.call("foo", .{});

    expectEqual(@as(usize, 0), i.state);
    resume i.frame;
    expectEqual(@as(usize, 1), i.state);
    resume i.frame;
    expectEqual(@as(usize, 2), i.state);
}

test "Interface with virtual async function implemented by a blocking function" {
    const AsyncIFace = Interface(struct {
        readBytes: async fn (*SelfType, []u8) anyerror!void,
    }, interface.Storage.Inline(8));

    const Impl = struct {
        const Self = @This();

        fn readBytes(self: Self, outBuf: []u8) void {
            for (outBuf) |*c| {
                c.* = 3;
            }
        }
    };

    var instance = try AsyncIFace.init(.{Impl{}});

    var buf: [256]u8 = undefined;
    try await async instance.call("readBytes", .{buf[0..]});

    expectEqual([_]u8{3} ** 256, buf);
}
