const std = @import("std");
const renderer = @import("../renderer.zig");

pub const DX13Renderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !DX13Renderer {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DX13Renderer) void {
        _ = self;
    }
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*DX13Renderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    _ = ptr;
    _ = desc;
    return error.DirectX13NotYetAvailable;
}

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    _ = ptr;
    _ = desc;
    return error.DirectX13NotYetAvailable;
}

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    _ = ptr;
    _ = desc;
    return error.DirectX13NotYetAvailable;
}

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    _ = ptr;
    _ = desc;
    return error.DirectX13NotYetAvailable;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    _ = ptr;
    return error.DirectX13NotYetAvailable;
}

fn waitIdleImpl(ptr: *anyopaque) void {
    _ = ptr;
}

const vtable = renderer.Renderer.VTable{
    .deinit = deinitImpl,
    .create_buffer = createBufferImpl,
    .create_texture = createTextureImpl,
    .create_pipeline = createPipelineImpl,
    .begin_render_pass = beginRenderPassImpl,
    .present = presentImpl,
    .wait_idle = waitIdleImpl,
};

pub fn create(allocator: std.mem.Allocator) !*renderer.Renderer {
    const impl = try allocator.create(DX13Renderer);
    impl.* = try DX13Renderer.init(allocator);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .directx13,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}