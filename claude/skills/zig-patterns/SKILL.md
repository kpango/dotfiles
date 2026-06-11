---
name: zig-patterns
description: Zig language idioms, comptime, memory management, error handling, and C interop patterns for safe, performant systems programming.
trigger: /zig-patterns
---

# Zig Patterns

## Core Principles

- No hidden control flow — every allocation, error, and branch is explicit
- Comptime is powerful but expensive in compile time; use judiciously
- Prefer stack allocation; heap-allocate only when lifetime requires it
- Every allocator must be passed explicitly — no global allocator

## Error Handling

```zig
// Error union: T!E
const result = try parseValue(input);

// Catch and handle
const value = parseValue(input) catch |err| switch (err) {
    error.InvalidInput => return error.BadRequest,
    error.Overflow => 0,
};

// errdefer for cleanup
fn openFile(path: []const u8) !std.fs.File {
    const file = try std.fs.cwd().openFile(path, .{});
    errdefer file.close();
    return file;
}
```

## Memory Management

```zig
// Always pass allocator explicitly
fn processItems(allocator: std.mem.Allocator, items: []const Item) ![]Result {
    const results = try allocator.alloc(Result, items.len);
    errdefer allocator.free(results);
    return results;
}

// Arena for request-scoped allocations
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const alloc = arena.allocator();

// Stack arrays for known sizes
var buf: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buf);
```

## Comptime

```zig
// Generic data structure
fn Stack(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        pub fn push(self: *@This(), item: T) !void {
            try self.items.append(item);
        }
    };
}

// Comptime type validation
fn assertNumeric(comptime T: type) void {
    comptime {
        const info = @typeInfo(T);
        if (info != .Int and info != .Float) {
            @compileError("Expected numeric type, got " ++ @typeName(T));
        }
    }
}
```

## Struct Patterns

```zig
// Packed struct for bit fields / C ABI
const Flags = packed struct(u32) {
    readable: bool,
    writable: bool,
    executable: bool,
    _padding: u29 = 0,
};

// Tagged union
const Value = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
};
```

## C Interop

```zig
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("mylib.h");
});

export fn myFunc(x: c_int) c_int {
    return x * 2;
}
```

## Testing

```zig
test "stack operations" {
    var stack = Stack(i32){ .items = std.ArrayList(i32).init(std.testing.allocator) };
    defer stack.items.deinit();
    try stack.push(1);
    try std.testing.expectEqual(@as(i32, 1), stack.items.items[0]);
}
```

## Anti-Patterns

- Global allocator — pass allocators explicitly
- Ignoring errors with `_ = try` — always handle or propagate
- Overusing comptime — degrades compile times; consider runtime
- Raw pointer arithmetic — use slices with bounds checking
- `@panic` in library code — return errors instead
