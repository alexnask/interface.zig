# Zig Interfaces
Easy solution for all your zig dynamic dispatch needs!

## Features
- Fully decoupled interfaces and implementations
- Control over the storage/ownership of interface objects
- Comptime support (including comptime-only interfaces)
- Async function partial support (blocking on [#4621](https://github.com/ziglang/zig/issues/4621))
- Optional function support
- Support for manually written vtables

## Example

```zig

const interface = @import("interface.zig");
const Interface = interface.Interface;
const SelfType = interface.SelfType;

// Let us create a Reader interface.
// We wrap it in our own struct to make function calls more natural.
const Reader = struct {
    pub const ReadError = error { CouldNotRead };

    const IFace = Interface(struct {

        // Our read requires a single non optional, non-const read function.
        read: fn (*SelfType, buf: []u8) ReadError!usize,

    }, interface.Storage.NonOwning); // This is a non owning interface, similar to Rust dyn traits.

    iface: IFace,

    // Wrap the interface's init, since the interface is non owning it requires no allocator argument.
    pub fn init(impl_ptr: var) Reader {
        return .{ .iface = try IFace.init(.{impl_ptr}) };
    }

    // Wrap the read function call
    pub fn read(self: *Reader, buf: []u8) ReadError!usize {
        return self.iface.call("read", .{buf});
    }

    // Define additional, non-dynamic functions!
    pub fn readAll(self: *Self, buf: []u8) ReadError!usize {
        var index: usize = 0;
        while (index != buf.len) {
            const partial_amt = try self.read(buffer[index..]);
            if (partial_amt == 0) return index;
            index += partial_amt;
        }
        return index;
    }
};

// Let's create an example reader
const ExampleReader = struct {
    state: u8,

    // Note that this reader cannot return an error, the return type
    // of our implementation functions only needs to coerce to the
    // interface's function return type.
    pub fn read(self: ExampleReader, buf: []u8) usize {
        for (buf) |*c| {
            c.* = self.state;
        }
        return buf.len;
    }
};

test "Use our reader interface!" {
    var example_reader = ExampleReader{ .state=42 };

    var reader = Reader.init(&example_reader);

    var buf: [100]u8 = undefined;
    _ = reader.read(&buf) catch unreachable;
}

```

See exampls.zig for more examples.