const std = @import("../std.zig");
const builtin = @import("builtin");
const root = @import("root");
const mem = std.mem;
const assert = std.debug.assert;
const warn = std.debug.warn;

pub const default_stack_size = 1 * 1024 * 1024;
pub const stack_size: usize = if (@hasDecl(root, "stack_size_std_io_OutStream"))
    root.stack_size_std_io_OutStream
else
    default_stack_size;

pub fn OutStream(comptime WriteError: type) type {
    return struct {
        const Self = @This();
        pub const Error = WriteError;
        pub const WriteFn = if (std.io.is_async)
            async fn (self: *Self, bytes: []const u8) Error!usize
        else
            fn (self: *Self, bytes: []const u8) Error!usize;

        writeFn: WriteFn,

        pub fn writeOnce(self: *Self, bytes: []const u8) Error!usize {
            if (bytes.len == 0) // TODO: Maybe assert this?
                return;

            try self.applyIndent();
            try self.writeNoIndent(bytes);
            if (bytes[bytes.len-1] == '\n')
                self.current_line_empty = true;
        }

        fn writeNoIndent(self: *Self, bytes: []const u8) Error!void {
            if (std.io.is_async) {
                // Let's not be writing 0xaa in safe modes for upwards of 4 MiB for every stream write.
                @setRuntimeSafety(false);
                var stack_frame: [stack_size]u8 align(std.Target.stack_align) = undefined;
                return await @asyncCall(&stack_frame, {}, self.writeFn, self, bytes);
            } else {
                return self.writeFn(self, bytes);
            }
        }

        pub fn write(self: *Self, bytes: []const u8) Error!void {
            var index: usize = 0;
            while (index != bytes.len) {
                index += try self.writeOnce(bytes[index..]);
            }
        }

        pub fn print(self: *Self, comptime format: []const u8, args: var) Error!void {
            return std.fmt.format(self, Error, write, format, args);
        }

        pub fn writeByte(self: *Self, byte: u8) Error!void {
            const array = [1]u8{byte};
            return self.write(&array);
        }

        pub fn writeByteNTimes(self: *Self, byte: u8, n: usize) Error!void {
            try self.applyIndent();
            try self.writeByteNTimesNoIndent(byte, n);
        }

        fn writeByteNTimesNoIndent(self: *Self, byte: u8, n: usize) Error!void {
            var bytes: [256]u8 = undefined;
            mem.set(u8, bytes[0..], byte);

            var remaining: usize = n;
            while (remaining > 0) {
                const to_write = std.math.min(remaining, bytes.len);
                try self.writeNoIndent(bytes[0..to_write]);
                remaining -= to_write;
            }
        }

        current_line_empty: bool = true,
        indent_stack: [255]u8 = undefined,
        indent_stack_top: u8 = 0,
        indent_one_shot_count: u8 = 0,
        indent_delta: u8 = 0,

        pub fn insertNewline(self: *Self) Error!void {
            warn("insertNewline\n", .{});
            try self.writeNoIndent("\n");
            self.current_line_empty = true;
            warn("~insertNewline\n", .{});
        }

        pub fn insertNewlines(self: *Self, n: usize) Error!void {
            warn("insertNewlines {}\n", .{n});
            var i: usize = 0;
            while (i < n) : (i += 1) try self.insertNewline();
            warn("~insertNewlines\n", .{});
        }

        pub fn maybeInsertNewline(self: *Self) Error!void {
            warn("maybeInsertNewline\n", .{});
            if (! self.current_line_empty)
                try self.insertNewline();
            warn("~maybeInsertNewline\n", .{});
        }

        /// Push default indentation
        pub fn pushIndent(self: *Self) void {
            // Doesn't actually write any indentation. Just primes the stream to be able to write the correct indentation if it needs to.
            warn("pushindent\n", .{});
            self.pushIndentN(self.indent_delta);
            warn("~pushindent\n", .{});
        }

        pub fn pushIndentN(self: *Self, n: u8) void {
            warn("pushindentN +{} {}\n", .{n, self.indent_stack_top});
            assert(self.indent_stack_top < std.math.maxInt(u8));
            self.indent_stack[self.indent_stack_top] = n;
            self.indent_stack_top += 1;
            warn("~pushindent +{} {}\n", .{n, self.indent_stack_top});
        }

        pub fn pushIndentOneShot(self: *Self) void {
            self.indent_one_shot_count += 1;
            self.pushIndent();
        }

        pub fn popIndent(self: *Self) void {
            warn("popindent {}\n", .{self.indent_stack_top});
            assert(self.indent_stack_top != 0);
            self.indent_stack_top -= 1;
        }

        fn applyIndent(self: *Self) Error!void {
            if (self.current_line_empty and self.indent_stack_top > 0)
                for (self.indent_stack[0..self.indent_stack_top]) |indent|
                    try self.writeByteNTimesNoIndent(' ', indent);
            self.indent_stack_top -= self.indent_one_shot_count;
            self.indent_one_shot_count = 0;
            self.current_line_empty = false;
        }

        /// Write a native-endian integer.
        pub fn writeIntNative(self: *Self, comptime T: type, value: T) Error!void {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            mem.writeIntNative(T, &bytes, value);
            return self.write(&bytes);
        }

        /// Write a foreign-endian integer.
        pub fn writeIntForeign(self: *Self, comptime T: type, value: T) Error!void {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            mem.writeIntForeign(T, &bytes, value);
            return self.write(&bytes);
        }

        pub fn writeIntLittle(self: *Self, comptime T: type, value: T) Error!void {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            mem.writeIntLittle(T, &bytes, value);
            return self.write(&bytes);
        }

        pub fn writeIntBig(self: *Self, comptime T: type, value: T) Error!void {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            mem.writeIntBig(T, &bytes, value);
            return self.write(&bytes);
        }

        pub fn writeInt(self: *Self, comptime T: type, value: T, endian: builtin.Endian) Error!void {
            var bytes: [(T.bit_count + 7) / 8]u8 = undefined;
            mem.writeInt(T, &bytes, value, endian);
            return self.write(&bytes);
        }
    };
}
