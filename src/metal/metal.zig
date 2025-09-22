const std = @import("std");
const renderer = @import("../renderer.zig");

const c = @cImport({
    @cInclude("Metal/Metal.h");
    @cInclude("QuartzCore/CAMetalLayer.h");
});

pub const MetalRenderer = struct {
    allocator: std.mem.Allocator,
    device: c.id,
    command_queue: c.id,
    swapchain: c.CAMetalLayer,
    pipeline_state: c.id,
    command_buffer: c.id,
    render_encoder: c.id,
    drawable: c.id,
    depth_texture: c.id,
    depth_stencil_state: c.id,
    vertex_buffer: c.id,
    uniform_buffer: c.id,

    pub fn init(allocator: std.mem.Allocator) !MetalRenderer {
        var self: MetalRenderer = undefined;
        self.allocator = allocator;

        self.device = c.MTLCreateSystemDefaultDevice();
        if (self.device == null) {
            return error.NoMetalDevice;
        }

        self.command_queue = c.objc_msgSend(self.device, c.sel_registerName("newCommandQueue"));
        if (self.command_queue == null) {
            return error.CommandQueueCreationFailed;
        }

        try self.createSwapchain();
        try self.createDepthStencilState();
        try self.createPipeline();

        return self;
    }

    fn createSwapchain(self: *MetalRenderer) !void {
        self.swapchain = c.objc_msgSend(c.objc_getClass("CAMetalLayer"), c.sel_registerName("layer"));
        if (self.swapchain == null) {
            return error.SwapchainCreationFailed;
        }

        _ = c.objc_msgSend(self.swapchain, c.sel_registerName("setDevice:"), self.device);
        _ = c.objc_msgSend(self.swapchain, c.sel_registerName("setPixelFormat:"), c.MTLPixelFormatBGRA8Unorm);
        _ = c.objc_msgSend(self.swapchain, c.sel_registerName("setFramebufferOnly:"), @as(c.BOOL, 1));

        const size = c.CGSize{ .width = 1280, .height = 720 };
        _ = c.objc_msgSend(self.swapchain, c.sel_registerName("setDrawableSize:"), size);
    }

    fn createDepthStencilState(self: *MetalRenderer) !void {
        const descriptor = c.objc_msgSend(c.objc_getClass("MTLDepthStencilDescriptor"), c.sel_registerName("new"));
        defer _ = c.objc_msgSend(descriptor, c.sel_registerName("release"));

        _ = c.objc_msgSend(descriptor, c.sel_registerName("setDepthCompareFunction:"), c.MTLCompareFunctionLess);
        _ = c.objc_msgSend(descriptor, c.sel_registerName("setDepthWriteEnabled:"), @as(c.BOOL, 1));

        self.depth_stencil_state = c.objc_msgSend(self.device, c.sel_registerName("newDepthStencilStateWithDescriptor:"), descriptor);
        if (self.depth_stencil_state == null) {
            return error.DepthStencilStateCreationFailed;
        }
    }

    fn createPipeline(self: *MetalRenderer) !void {
        const library = c.objc_msgSend(self.device, c.sel_registerName("newDefaultLibrary"));
        if (library == null) {
            return error.LibraryCreationFailed;
        }
        defer _ = c.objc_msgSend(library, c.sel_registerName("release"));

        const vertex_function = c.objc_msgSend(library, c.sel_registerName("newFunctionWithName:"), c.objc_msgSend(c.objc_getClass("NSString"), c.sel_registerName("stringWithUTF8String:"), "vertex_main"));
        const fragment_function = c.objc_msgSend(library, c.sel_registerName("newFunctionWithName:"), c.objc_msgSend(c.objc_getClass("NSString"), c.sel_registerName("stringWithUTF8String:"), "fragment_main"));

        if (vertex_function == null or fragment_function == null) {
            return error.ShaderFunctionNotFound;
        }

        defer {
            _ = c.objc_msgSend(vertex_function, c.sel_registerName("release"));
            _ = c.objc_msgSend(fragment_function, c.sel_registerName("release"));
        }

        const pipeline_descriptor = c.objc_msgSend(c.objc_getClass("MTLRenderPipelineDescriptor"), c.sel_registerName("new"));
        defer _ = c.objc_msgSend(pipeline_descriptor, c.sel_registerName("release"));

        _ = c.objc_msgSend(pipeline_descriptor, c.sel_registerName("setVertexFunction:"), vertex_function);
        _ = c.objc_msgSend(pipeline_descriptor, c.sel_registerName("setFragmentFunction:"), fragment_function);

        const color_attachments = c.objc_msgSend(pipeline_descriptor, c.sel_registerName("colorAttachments"));
        const attachment0 = c.objc_msgSend(color_attachments, c.sel_registerName("objectAtIndexedSubscript:"), @as(c.NSUInteger, 0));
        _ = c.objc_msgSend(attachment0, c.sel_registerName("setPixelFormat:"), c.MTLPixelFormatBGRA8Unorm);

        _ = c.objc_msgSend(pipeline_descriptor, c.sel_registerName("setDepthAttachmentPixelFormat:"), c.MTLPixelFormatDepth32Float);

        var err: c.NSError = null;
        self.pipeline_state = c.objc_msgSend(self.device, c.sel_registerName("newRenderPipelineStateWithDescriptor:error:"), pipeline_descriptor, &err);

        if (self.pipeline_state == null) {
            if (err != null) {
                _ = c.objc_msgSend(err, c.sel_registerName("release"));
            }
            return error.PipelineStateCreationFailed;
        }
    }

    fn createDepthTexture(self: *MetalRenderer, width: usize, height: usize) !void {
        const texture_descriptor = c.objc_msgSend(c.objc_getClass("MTLTextureDescriptor"), c.sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"), c.MTLPixelFormatDepth32Float, width, height, @as(c.BOOL, 0));

        _ = c.objc_msgSend(texture_descriptor, c.sel_registerName("setUsage:"), c.MTLTextureUsageRenderTarget);
        _ = c.objc_msgSend(texture_descriptor, c.sel_registerName("setStorageMode:"), c.MTLStorageModePrivate);

        self.depth_texture = c.objc_msgSend(self.device, c.sel_registerName("newTextureWithDescriptor:"), texture_descriptor);
        if (self.depth_texture == null) {
            return error.DepthTextureCreationFailed;
        }
    }

    pub fn deinit(self: *MetalRenderer) void {
        if (self.depth_texture != null) {
            _ = c.objc_msgSend(self.depth_texture, c.sel_registerName("release"));
        }
        if (self.vertex_buffer != null) {
            _ = c.objc_msgSend(self.vertex_buffer, c.sel_registerName("release"));
        }
        if (self.uniform_buffer != null) {
            _ = c.objc_msgSend(self.uniform_buffer, c.sel_registerName("release"));
        }
        _ = c.objc_msgSend(self.depth_stencil_state, c.sel_registerName("release"));
        _ = c.objc_msgSend(self.pipeline_state, c.sel_registerName("release"));
        _ = c.objc_msgSend(self.swapchain, c.sel_registerName("release"));
        _ = c.objc_msgSend(self.command_queue, c.sel_registerName("release"));
        _ = c.objc_msgSend(self.device, c.sel_registerName("release"));
    }

    pub fn beginFrame(self: *MetalRenderer) !void {
        self.drawable = c.objc_msgSend(self.swapchain, c.sel_registerName("nextDrawable"));
        if (self.drawable == null) {
            return error.NoDrawable;
        }

        self.command_buffer = c.objc_msgSend(self.command_queue, c.sel_registerName("commandBuffer"));
        if (self.command_buffer == null) {
            return error.CommandBufferCreationFailed;
        }
    }

    pub fn endFrame(self: *MetalRenderer) void {
        _ = c.objc_msgSend(self.command_buffer, c.sel_registerName("presentDrawable:"), self.drawable);
        _ = c.objc_msgSend(self.command_buffer, c.sel_registerName("commit"));
    }
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*MetalRenderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    const self = @as(*MetalRenderer, @ptrCast(@alignCast(ptr)));

    const buffer = c.objc_msgSend(self.device, c.sel_registerName("newBufferWithLength:options:"), desc.size, c.MTLResourceStorageModeShared);
    if (buffer == null) {
        return error.BufferCreationFailed;
    }

    const result = try self.allocator.create(renderer.Buffer);
    result.* = .{
        .handle = buffer,
        .size = desc.size,
        .usage = desc.usage,
        .vtable = &buffer_vtable,
    };

    return result;
}

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
}

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
}

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    const self = @as(*MetalRenderer, @ptrCast(@alignCast(ptr)));
    try self.beginFrame();
    self.endFrame();
}

fn waitIdleImpl(ptr: *anyopaque) void {
    const self = @as(*MetalRenderer, @ptrCast(@alignCast(ptr)));
    _ = c.objc_msgSend(self.command_queue, c.sel_registerName("waitUntilCompleted"));
}

fn bufferDeinitImpl(ptr: *anyopaque) void {
    _ = c.objc_msgSend(@as(c.id, @ptrCast(ptr)), c.sel_registerName("release"));
}

fn bufferMapImpl(ptr: *anyopaque) anyerror![]u8 {
    const contents = c.objc_msgSend(@as(c.id, @ptrCast(ptr)), c.sel_registerName("contents"));
    const length = c.objc_msgSend(@as(c.id, @ptrCast(ptr)), c.sel_registerName("length"));
    return @as([*]u8, @ptrCast(contents))[0..@as(usize, @intCast(length))];
}

fn bufferUnmapImpl(ptr: *anyopaque) void {
    _ = ptr;
}

fn bufferWriteImpl(ptr: *anyopaque, data: []const u8, offset: usize) void {
    const contents = c.objc_msgSend(@as(c.id, @ptrCast(ptr)), c.sel_registerName("contents"));
    const dst = @as([*]u8, @ptrCast(contents)) + offset;
    @memcpy(dst[0..data.len], data);
}

const buffer_vtable = renderer.Buffer.VTable{
    .deinit = bufferDeinitImpl,
    .map = bufferMapImpl,
    .unmap = bufferUnmapImpl,
    .write = bufferWriteImpl,
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
    const impl = try allocator.create(MetalRenderer);
    impl.* = try MetalRenderer.init(allocator);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .metal,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}