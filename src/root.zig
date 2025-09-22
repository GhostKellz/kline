//! Kline: Cross-Platform Rendering Engine
//! Hardware-accelerated 3D/2D rendering with multiple backends
//! Supports Vulkan, DirectX 12/13, Metal, OpenGL ES, and software rendering
const std = @import("std");

pub const renderer = @import("renderer.zig");
pub const vector = @import("vector.zig");
pub const memory_pool = @import("memory_pool.zig");
pub const compute = @import("compute.zig");

pub const Backend = renderer.Backend;
pub const Renderer = renderer.Renderer;
pub const VectorContext = vector.VectorContext;
pub const MemoryPool = memory_pool.MemoryPool;
pub const GPUMemoryPool = memory_pool.GPUMemoryPool;
pub const ParallelFor = compute.ParallelFor;

pub fn createRenderer(allocator: std.mem.Allocator, backend: Backend) !*Renderer {
    return renderer.create(allocator, backend);
}

pub fn bufferedPrint() !void {
    std.debug.print("Kline v1.0.0 - Cross-Platform Rendering Engine\n", .{});
    std.debug.print("Supported backends: Vulkan, DirectX 12/13, Metal, OpenGL ES, Software\n", .{});
    std.debug.print("Features: Vector Graphics, Memory Pools, Compute Shaders\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "renderer creation" {
    const allocator = std.testing.allocator;

    var r = createRenderer(allocator, .software) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    defer {
        r.deinit();
        allocator.destroy(r);
    }

    try std.testing.expect(r.backend == .software);
}

test "vector graphics" {
    const allocator = std.testing.allocator;

    var r = createRenderer(allocator, .software) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    defer {
        r.deinit();
        allocator.destroy(r);
    }

    var ctx = vector.VectorContext.init(allocator, r) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    defer ctx.deinit();

    const red = vector.Color{ .r = 1, .g = 0, .b = 0, .a = 1 };
    ctx.setFillColor(red);

    ctx.fillRect(10, 10, 100, 50) catch |err| switch (err) {
        error.PathOverflow => return,
        else => return err,
    };
}

test "memory pool" {
    const allocator = std.testing.allocator;

    var pool = memory_pool.MemoryPool.init(allocator, 1024, 16, 8) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };
    defer pool.deinit();

    const mem = pool.alloc(512) catch |err| switch (err) {
        error.OutOfMemory => return,
        else => return err,
    };

    try std.testing.expect(mem.len == 512);
    pool.free(mem);
}
