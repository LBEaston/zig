const std = @import("../std.zig");
const builtin = @import("builtin");
const root = @import("root");
const mem = std.mem;
const assert = std.debug.assert;

pub fn AutoIndentingStream(comptime WriteError: type) type {
    return struct {
        const Self = @This();
        pub const Error = WriteError;
        pub const WriteFn = fn (self: *Self, bytes: []const u8) Error!usize;

        writeFn: WriteFn,

        pub fn write(self: *Self, bytes: []const u8) Error!void {
            if (bytes.len == 0)
                return;

            try self.applyIndent();
            try self.writeNoIndent(bytes);
            if (bytes[bytes.len - 1] == '\n')
                self.resetLine();
        }

        fn writeNoIndent(self: *Self, bytes: []const u8) Error!void {
            const written = try self.writeFn(self, bytes);
            assert(written == bytes.len); // Correct slicing of bytes should be done further downstream
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
        indent_one_shot_count: u8 = 0, // automatically popped when applied
        applied_indent: u8 = 0, // the most recently applied indent
        indent_next_line: u8 = 0, // not used until the next line
        indent_delta: u8 = 0,

        pub fn insertNewline(self: *Self) Error!void {
            try self.writeNoIndent("\n");
            self.resetLine();
        }

        fn resetLine(self: *Self) void {
            self.current_line_empty = true;
            self.indent_next_line = 0;
        }

        /// Insert a newline unless the current line is blank
        pub fn maybeInsertNewline(self: *Self) Error!void {
            if (!self.current_line_empty)
                try self.insertNewline();
        }

        /// Push default indentation
        pub fn pushIndent(self: *Self) void {
            // Doesn't actually write any indentation. Just primes the stream to be able to write the correct indentation if it needs to.
            self.pushIndentN(self.indent_delta);
        }

        /// Push an indent of arbitrary width
        pub fn pushIndentN(self: *Self, n: u8) void {
            assert(self.indent_stack_top < std.math.maxInt(u8));
            self.indent_stack[self.indent_stack_top] = n;
            self.indent_stack_top += 1;
        }

        /// Push an indent that is automatically popped after being applied
        pub fn pushIndentOneShot(self: *Self) void {
            self.indent_one_shot_count += 1;
            self.pushIndent();
        }

        /// Turns all one-shot indents into regular indents
        /// Returns number of indents that must now be manually popped
        pub fn lockOneShotIndent(self: *Self) u8 {
            var locked_count = self.indent_one_shot_count;
            self.indent_one_shot_count = 0;
            return locked_count;
        }

        /// Push an indent that should not take effect until the next line
        pub fn pushIndentNextLine(self: *Self) void {
            self.indent_next_line += 1;
            self.pushIndent();
        }

        pub fn popIndent(self: *Self) void {
            assert(self.indent_stack_top != 0);
            self.indent_stack_top -= 1;
        }

        /// Writes ' ' bytes if the current line is empty
        fn applyIndent(self: *Self) Error!void {
            const current_indent = self.currentIndent();
            if (self.current_line_empty and current_indent > 0) {
                try self.writeByteNTimesNoIndent(' ', current_indent);
                self.applied_indent = current_indent;
            }

            self.indent_stack_top -= self.indent_one_shot_count;
            self.indent_one_shot_count = 0;
            self.current_line_empty = false;
        }

        /// Checks to see if the most recent indentation exceeds the currently pushed indents
        pub fn isLineOverIndented(self: *Self) bool {
            if (self.current_line_empty) return false;
            return self.applied_indent > self.currentIndent();
        }

        fn currentIndent(self: *Self) u8 {
            var indent_current: u8 = 0;
            if (self.indent_stack_top > 0) {
                const stack_top = self.indent_stack_top - self.indent_next_line;
                for (self.indent_stack[0..stack_top]) |indent| {
                    indent_current += indent;
                }
            }
            return indent_current;
        }
    };
}
