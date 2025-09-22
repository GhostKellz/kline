const std = @import("std");
const renderer = @import("../renderer.zig");

pub const SoftwareRenderer = struct {
    allocator: std.mem.Allocator,
    framebuffer: []u32,
    depth_buffer: []f32,
    width: u32,
    height: u32,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !SoftwareRenderer {
        const pixel_count = width * height;
        const framebuffer = try allocator.alloc(u32, pixel_count);
        errdefer allocator.free(framebuffer);

        const depth_buffer = try allocator.alloc(f32, pixel_count);
        errdefer allocator.free(depth_buffer);

        @memset(framebuffer, 0xFF000000);
        @memset(depth_buffer, 1.0);

        return .{
            .allocator = allocator,
            .framebuffer = framebuffer,
            .depth_buffer = depth_buffer,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *SoftwareRenderer) void {
        self.allocator.free(self.depth_buffer);
        self.allocator.free(self.framebuffer);
    }

    pub fn clear(self: *SoftwareRenderer, color: u32) void {
        @memset(self.framebuffer, color);
        @memset(self.depth_buffer, 1.0);
    }

    pub fn setPixel(self: *SoftwareRenderer, x: i32, y: i32, color: u32) void {
        if (x < 0 or y < 0) return;
        const ux = @as(u32, @intCast(x));
        const uy = @as(u32, @intCast(y));
        if (ux >= self.width or uy >= self.height) return;

        const index = uy * self.width + ux;
        self.framebuffer[index] = color;
    }

    pub fn drawLine(self: *SoftwareRenderer, x0: i32, y0: i32, x1: i32, y1: i32, color: u32) void {
        var x = x0;
        var y = y0;
        const dx = std.math.absInt(x1 - x0) catch 0;
        const dy = std.math.absInt(y1 - y0) catch 0;
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx - dy;

        while (true) {
            self.setPixel(x, y, color);

            if (x == x1 and y == y1) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    pub fn fillTriangle(self: *SoftwareRenderer, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
        var vx0 = x0;
        var vy0 = y0;
        var vx1 = x1;
        var vy1 = y1;
        var vx2 = x2;
        var vy2 = y2;

        if (vy0 > vy1) {
            std.mem.swap(i32, &vx0, &vx1);
            std.mem.swap(i32, &vy0, &vy1);
        }
        if (vy1 > vy2) {
            std.mem.swap(i32, &vx1, &vx2);
            std.mem.swap(i32, &vy1, &vy2);
        }
        if (vy0 > vy1) {
            std.mem.swap(i32, &vx0, &vx1);
            std.mem.swap(i32, &vy0, &vy1);
        }

        const total_height = vy2 - vy0;
        if (total_height == 0) return;

        var y = vy0;
        while (y <= vy2) : (y += 1) {
            const first_half = y <= vy1;
            const segment_height = if (first_half) vy1 - vy0 + 1 else vy2 - vy1 + 1;
            if (segment_height == 0) continue;

            const alpha = @as(f32, @floatFromInt(y - vy0)) / @as(f32, @floatFromInt(total_height));
            const beta = if (first_half)
                @as(f32, @floatFromInt(y - vy0)) / @as(f32, @floatFromInt(segment_height))
            else
                @as(f32, @floatFromInt(y - vy1)) / @as(f32, @floatFromInt(segment_height));

            var xa = @as(i32, @intFromFloat(@as(f32, @floatFromInt(vx0)) + @as(f32, @floatFromInt(vx2 - vx0)) * alpha));
            var xb = if (first_half)
                @as(i32, @intFromFloat(@as(f32, @floatFromInt(vx0)) + @as(f32, @floatFromInt(vx1 - vx0)) * beta))
            else
                @as(i32, @intFromFloat(@as(f32, @floatFromInt(vx1)) + @as(f32, @floatFromInt(vx2 - vx1)) * beta));

            if (xa > xb) std.mem.swap(i32, &xa, &xb);

            var x = xa;
            while (x <= xb) : (x += 1) {
                self.setPixel(x, y, color);
            }
        }
    }

    pub fn fillRect(self: *SoftwareRenderer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        const x_start = @max(0, x);
        const y_start = @max(0, y);
        const x_end = @min(self.width, @as(u32, @intCast(@max(0, x))) + w);
        const y_end = @min(self.height, @as(u32, @intCast(@max(0, y))) + h);

        var py = @as(u32, @intCast(y_start));
        while (py < y_end) : (py += 1) {
            var px = @as(u32, @intCast(x_start));
            while (px < x_end) : (px += 1) {
                const index = py * self.width + px;
                self.framebuffer[index] = color;
            }
        }
    }
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*SoftwareRenderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    const self = @as(*SoftwareRenderer, @ptrCast(@alignCast(ptr)));

    const data = try self.allocator.alloc(u8, desc.size);
    @memset(data, 0);

    const buffer = try self.allocator.create(renderer.Buffer);
    buffer.* = .{
        .handle = data.ptr,
        .size = desc.size,
        .usage = desc.usage,
        .vtable = &buffer_vtable,
    };

    return buffer;
}

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    const self = @as(*SoftwareRenderer, @ptrCast(@alignCast(ptr)));

    const pixel_count = desc.width * desc.height * desc.depth;
    const data = try self.allocator.alloc(u32, pixel_count);
    @memset(data, 0xFF000000);

    const texture = try self.allocator.create(renderer.Texture);
    texture.* = .{
        .handle = data.ptr,
        .width = desc.width,
        .height = desc.height,
        .format = desc.format,
        .vtable = &texture_vtable,
    };

    return texture;
}

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    const self = @as(*SoftwareRenderer, @ptrCast(@alignCast(ptr)));
    _ = desc;

    const pipeline = try self.allocator.create(renderer.Pipeline);
    pipeline.* = .{
        .handle = undefined,
        .vtable = &pipeline_vtable,
    };

    return pipeline;
}

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    const self = @as(*SoftwareRenderer, @ptrCast(@alignCast(ptr)));

    if (desc.color_attachments.len > 0) {
        const clear_color = desc.color_attachments[0].clear_color;
        const r = @as(u8, @intFromFloat(@min(255, clear_color[0] * 255)));
        const g = @as(u8, @intFromFloat(@min(255, clear_color[1] * 255)));
        const b = @as(u8, @intFromFloat(@min(255, clear_color[2] * 255)));
        const a = @as(u8, @intFromFloat(@min(255, clear_color[3] * 255)));
        const color = (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
        self.clear(color);
    }

    const pass = try self.allocator.create(renderer.RenderPass);
    pass.* = .{
        .handle = self,
        .vtable = &render_pass_vtable,
    };

    return pass;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    _ = ptr;
}

fn waitIdleImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn bufferDeinitImpl(ptr: *anyopaque) void {
    const data = @as([*]u8, @ptrCast(@alignCast(ptr)));
    _ = data;
}

fn bufferMapImpl(ptr: *anyopaque) anyerror![]u8 {
    _ = ptr;
    return error.NotImplemented;
}

fn bufferUnmapImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn bufferWriteImpl(ptr: *anyopaque, data: []const u8, offset: usize) void {
    const dst = @as([*]u8, @ptrCast(@alignCast(ptr))) + offset;
    @memcpy(dst[0..data.len], data);
}

fn textureDeinitImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn textureCreateViewImpl(ptr: *anyopaque) anyerror!*renderer.TextureView {
    _ = ptr;
    return error.NotImplemented;
}

fn pipelineDeinitImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn renderPassEndImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn renderPassSetPipelineImpl(ptr: *anyopaque, pipeline: *renderer.Pipeline) void {
    _ = ptr;
    _ = pipeline;
}

fn renderPassSetVertexBufferImpl(ptr: *anyopaque, slot: u32, buffer: *renderer.Buffer) void {
    _ = ptr;
    _ = slot;
    _ = buffer;
}

fn renderPassSetIndexBufferImpl(ptr: *anyopaque, buffer: *renderer.Buffer, format: renderer.IndexFormat) void {
    _ = ptr;
    _ = buffer;
    _ = format;
}

fn renderPassDrawImpl(ptr: *anyopaque, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
    _ = ptr;
    _ = vertex_count;
    _ = instance_count;
    _ = first_vertex;
    _ = first_instance;
}

fn renderPassDrawIndexedImpl(ptr: *anyopaque, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
    _ = ptr;
    _ = index_count;
    _ = instance_count;
    _ = first_index;
    _ = vertex_offset;
    _ = first_instance;
}

const buffer_vtable = renderer.Buffer.VTable{
    .deinit = bufferDeinitImpl,
    .map = bufferMapImpl,
    .unmap = bufferUnmapImpl,
    .write = bufferWriteImpl,
};

const texture_vtable = renderer.Texture.VTable{
    .deinit = textureDeinitImpl,
    .create_view = textureCreateViewImpl,
};

const pipeline_vtable = renderer.Pipeline.VTable{
    .deinit = pipelineDeinitImpl,
};

const render_pass_vtable = renderer.RenderPass.VTable{
    .end = renderPassEndImpl,
    .set_pipeline = renderPassSetPipelineImpl,
    .set_vertex_buffer = renderPassSetVertexBufferImpl,
    .set_index_buffer = renderPassSetIndexBufferImpl,
    .draw = renderPassDrawImpl,
    .draw_indexed = renderPassDrawIndexedImpl,
};

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
    const impl = try allocator.create(SoftwareRenderer);
    impl.* = try SoftwareRenderer.init(allocator, 1280, 720);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .software,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}