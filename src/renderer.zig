const std = @import("std");

pub const Backend = enum {
    vulkan,
    directx12,
    directx13,
    metal,
    opengl_es,
    software,
};

pub const RenderTargetFormat = enum {
    rgba8,
    rgba16f,
    rgba32f,
    depth24_stencil8,
    depth32f,
};

pub const BufferUsage = packed struct {
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
    storage: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    indirect: bool = false,
};

pub const TextureUsage = packed struct {
    sampled: bool = false,
    storage: bool = false,
    render_target: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const PrimitiveType = enum {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
};

pub const CompareOp = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,
};

pub const BlendOp = enum {
    add,
    subtract,
    reverse_subtract,
    min,
    max,
};

pub const CullMode = enum {
    none,
    front,
    back,
};

pub const FrontFace = enum {
    counter_clockwise,
    clockwise,
};

pub const BufferDescriptor = struct {
    size: usize,
    usage: BufferUsage,
    mapped_at_creation: bool = false,
};

pub const TextureDescriptor = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    sample_count: u32 = 1,
    format: RenderTargetFormat,
    usage: TextureUsage,
};

pub const RenderPassDescriptor = struct {
    color_attachments: []ColorAttachment,
    depth_stencil_attachment: ?DepthStencilAttachment = null,
};

pub const ColorAttachment = struct {
    view: *TextureView,
    resolve_target: ?*TextureView = null,
    load_op: LoadOp,
    store_op: StoreOp,
    clear_color: [4]f32 = .{ 0, 0, 0, 1 },
};

pub const DepthStencilAttachment = struct {
    view: *TextureView,
    depth_load_op: LoadOp,
    depth_store_op: StoreOp,
    depth_clear_value: f32 = 1.0,
    stencil_load_op: LoadOp,
    stencil_store_op: StoreOp,
    stencil_clear_value: u32 = 0,
};

pub const LoadOp = enum {
    clear,
    load,
};

pub const StoreOp = enum {
    store,
    discard,
};

pub const PipelineDescriptor = struct {
    vertex_shader: []const u8,
    fragment_shader: []const u8,
    vertex_layout: VertexLayout,
    primitive_type: PrimitiveType = .triangle_list,
    cull_mode: CullMode = .back,
    front_face: FrontFace = .counter_clockwise,
    depth_test: bool = true,
    depth_write: bool = true,
    depth_compare: CompareOp = .less,
    blend_enabled: bool = false,
    blend_src_factor: BlendFactor = .one,
    blend_dst_factor: BlendFactor = .zero,
    blend_op: BlendOp = .add,
};

pub const VertexLayout = struct {
    attributes: []const VertexAttribute,
    stride: u32,
};

pub const VertexAttribute = struct {
    format: AttributeFormat,
    offset: u32,
    location: u32,
};

pub const AttributeFormat = enum {
    float32,
    float32x2,
    float32x3,
    float32x4,
    uint32,
    uint32x2,
    uint32x3,
    uint32x4,
    sint32,
    sint32x2,
    sint32x3,
    sint32x4,
};

pub const Renderer = struct {
    backend: Backend,
    impl: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        create_buffer: *const fn (*anyopaque, BufferDescriptor) anyerror!*Buffer,
        create_texture: *const fn (*anyopaque, TextureDescriptor) anyerror!*Texture,
        create_pipeline: *const fn (*anyopaque, PipelineDescriptor) anyerror!*Pipeline,
        begin_render_pass: *const fn (*anyopaque, RenderPassDescriptor) anyerror!*RenderPass,
        present: *const fn (*anyopaque) anyerror!void,
        wait_idle: *const fn (*anyopaque) void,
    };

    pub fn deinit(self: *Renderer) void {
        self.vtable.deinit(self.impl);
    }

    pub fn createBuffer(self: *Renderer, desc: BufferDescriptor) !*Buffer {
        return self.vtable.create_buffer(self.impl, desc);
    }

    pub fn createTexture(self: *Renderer, desc: TextureDescriptor) !*Texture {
        return self.vtable.create_texture(self.impl, desc);
    }

    pub fn createPipeline(self: *Renderer, desc: PipelineDescriptor) !*Pipeline {
        return self.vtable.create_pipeline(self.impl, desc);
    }

    pub fn beginRenderPass(self: *Renderer, desc: RenderPassDescriptor) !*RenderPass {
        return self.vtable.begin_render_pass(self.impl, desc);
    }

    pub fn present(self: *Renderer) !void {
        return self.vtable.present(self.impl);
    }

    pub fn waitIdle(self: *Renderer) void {
        self.vtable.wait_idle(self.impl);
    }
};

pub const Buffer = struct {
    handle: *anyopaque,
    size: usize,
    usage: BufferUsage,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        map: *const fn (*anyopaque) anyerror![]u8,
        unmap: *const fn (*anyopaque) void,
        write: *const fn (*anyopaque, []const u8, usize) void,
    };

    pub fn deinit(self: *Buffer) void {
        self.vtable.deinit(self.handle);
    }

    pub fn map(self: *Buffer) ![]u8 {
        return self.vtable.map(self.handle);
    }

    pub fn unmap(self: *Buffer) void {
        self.vtable.unmap(self.handle);
    }

    pub fn write(self: *Buffer, data: []const u8, offset: usize) void {
        self.vtable.write(self.handle, data, offset);
    }
};

pub const Texture = struct {
    handle: *anyopaque,
    width: u32,
    height: u32,
    format: RenderTargetFormat,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        create_view: *const fn (*anyopaque) anyerror!*TextureView,
    };

    pub fn deinit(self: *Texture) void {
        self.vtable.deinit(self.handle);
    }

    pub fn createView(self: *Texture) !*TextureView {
        return self.vtable.create_view(self.handle);
    }
};

pub const TextureView = struct {
    handle: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
    };

    pub fn deinit(self: *TextureView) void {
        self.vtable.deinit(self.handle);
    }
};

pub const Pipeline = struct {
    handle: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
    };

    pub fn deinit(self: *Pipeline) void {
        self.vtable.deinit(self.handle);
    }
};

pub const RenderPass = struct {
    handle: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        end: *const fn (*anyopaque) void,
        set_pipeline: *const fn (*anyopaque, *Pipeline) void,
        set_vertex_buffer: *const fn (*anyopaque, u32, *Buffer) void,
        set_index_buffer: *const fn (*anyopaque, *Buffer, IndexFormat) void,
        draw: *const fn (*anyopaque, u32, u32, u32, u32) void,
        draw_indexed: *const fn (*anyopaque, u32, u32, u32, i32, u32) void,
    };

    pub fn end(self: *RenderPass) void {
        self.vtable.end(self.handle);
    }

    pub fn setPipeline(self: *RenderPass, pipeline: *Pipeline) void {
        self.vtable.set_pipeline(self.handle, pipeline);
    }

    pub fn setVertexBuffer(self: *RenderPass, slot: u32, buffer: *Buffer) void {
        self.vtable.set_vertex_buffer(self.handle, slot, buffer);
    }

    pub fn setIndexBuffer(self: *RenderPass, buffer: *Buffer, format: IndexFormat) void {
        self.vtable.set_index_buffer(self.handle, buffer, format);
    }

    pub fn draw(self: *RenderPass, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.vtable.draw(self.handle, vertex_count, instance_count, first_vertex, first_instance);
    }

    pub fn drawIndexed(self: *RenderPass, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        self.vtable.draw_indexed(self.handle, index_count, instance_count, first_index, vertex_offset, first_instance);
    }
};

pub const IndexFormat = enum {
    uint16,
    uint32,
};

pub fn create(allocator: std.mem.Allocator, backend: Backend) !*Renderer {
    return switch (backend) {
        .vulkan => error.VulkanNotAvailable,
        .directx12 => error.DirectX12NotAvailable,
        .directx13 => @import("dx13/dx13.zig").create(allocator),
        .metal => error.MetalNotAvailable,
        .opengl_es => error.OpenGLESNotAvailable,
        .software => @import("software/software.zig").create(allocator),
    };
}