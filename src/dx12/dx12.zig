const std = @import("std");
const renderer = @import("../renderer.zig");
const windows = std.os.windows;

const c = @cImport({
    @cInclude("d3d12.h");
    @cInclude("dxgi1_6.h");
    @cInclude("d3dcompiler.h");
});

pub const DX12Renderer = struct {
    allocator: std.mem.Allocator,
    device: *c.ID3D12Device,
    command_queue: *c.ID3D12CommandQueue,
    swapchain: *c.IDXGISwapChain3,
    descriptor_heap: *c.ID3D12DescriptorHeap,
    rtv_descriptor_size: u32,
    command_allocator: *c.ID3D12CommandAllocator,
    command_list: *c.ID3D12GraphicsCommandList,
    fence: *c.ID3D12Fence,
    fence_event: windows.HANDLE,
    fence_value: u64,
    frame_index: u32,
    viewport: c.D3D12_VIEWPORT,
    scissor_rect: c.D3D12_RECT,
    render_targets: [2]*c.ID3D12Resource,
    root_signature: *c.ID3D12RootSignature,

    pub fn init(allocator: std.mem.Allocator, window_handle: windows.HWND) !DX12Renderer {
        var self: DX12Renderer = undefined;
        self.allocator = allocator;
        self.fence_value = 0;

        try self.createDevice();
        try self.createCommandQueue();
        try self.createSwapChain(window_handle);
        try self.createDescriptorHeaps();
        try self.createFrameResources();
        try self.createCommandAllocator();
        try self.createCommandList();
        try self.createFence();
        try self.createRootSignature();

        return self;
    }

    fn createDevice(self: *DX12Renderer) !void {
        var factory: *c.IDXGIFactory4 = undefined;
        var hr = c.CreateDXGIFactory2(0, &c.IID_IDXGIFactory4, @ptrCast(&factory));
        if (hr < 0) return error.FactoryCreationFailed;
        defer _ = factory.*.lpVtbl.*.Release.?(factory);

        var adapter: *c.IDXGIAdapter1 = undefined;
        var adapter_index: u32 = 0;
        var best_adapter: ?*c.IDXGIAdapter1 = null;
        var best_vram: usize = 0;

        while (factory.*.lpVtbl.*.EnumAdapters1.?(factory, adapter_index, &adapter) != c.DXGI_ERROR_NOT_FOUND) : (adapter_index += 1) {
            var desc: c.DXGI_ADAPTER_DESC1 = undefined;
            _ = adapter.*.lpVtbl.*.GetDesc1.?(adapter, &desc);

            if (desc.Flags & c.DXGI_ADAPTER_FLAG_SOFTWARE != 0) {
                _ = adapter.*.lpVtbl.*.Release.?(adapter);
                continue;
            }

            if (c.D3D12CreateDevice(@ptrCast(adapter), c.D3D_FEATURE_LEVEL_12_0, &c.IID_ID3D12Device, null) >= 0) {
                if (desc.DedicatedVideoMemory > best_vram) {
                    if (best_adapter) |old| {
                        _ = old.*.lpVtbl.*.Release.?(old);
                    }
                    best_adapter = adapter;
                    best_vram = desc.DedicatedVideoMemory;
                } else {
                    _ = adapter.*.lpVtbl.*.Release.?(adapter);
                }
            }
        }

        if (best_adapter == null) {
            return error.NoSuitableAdapter;
        }

        hr = c.D3D12CreateDevice(
            @ptrCast(best_adapter),
            c.D3D_FEATURE_LEVEL_12_0,
            &c.IID_ID3D12Device,
            @ptrCast(&self.device),
        );

        _ = best_adapter.?.*.lpVtbl.*.Release.?(best_adapter.?);

        if (hr < 0) return error.DeviceCreationFailed;
    }

    fn createCommandQueue(self: *DX12Renderer) !void {
        const desc = c.D3D12_COMMAND_QUEUE_DESC{
            .Type = c.D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = c.D3D12_COMMAND_QUEUE_PRIORITY_NORMAL,
            .Flags = c.D3D12_COMMAND_QUEUE_FLAG_NONE,
            .NodeMask = 0,
        };

        const hr = self.device.*.lpVtbl.*.CreateCommandQueue.?(
            self.device,
            &desc,
            &c.IID_ID3D12CommandQueue,
            @ptrCast(&self.command_queue),
        );

        if (hr < 0) return error.CommandQueueCreationFailed;
    }

    fn createSwapChain(self: *DX12Renderer, window_handle: windows.HWND) !void {
        var factory: *c.IDXGIFactory4 = undefined;
        var hr = c.CreateDXGIFactory2(0, &c.IID_IDXGIFactory4, @ptrCast(&factory));
        if (hr < 0) return error.FactoryCreationFailed;
        defer _ = factory.*.lpVtbl.*.Release.?(factory);

        const desc = c.DXGI_SWAP_CHAIN_DESC1{
            .Width = 1280,
            .Height = 720,
            .Format = c.DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = c.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = c.DXGI_SCALING_NONE,
            .SwapEffect = c.DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .AlphaMode = c.DXGI_ALPHA_MODE_UNSPECIFIED,
            .Flags = 0,
        };

        var swap_chain: *c.IDXGISwapChain1 = undefined;
        hr = factory.*.lpVtbl.*.CreateSwapChainForHwnd.?(
            factory,
            @ptrCast(self.command_queue),
            window_handle,
            &desc,
            null,
            null,
            &swap_chain,
        );

        if (hr < 0) return error.SwapChainCreationFailed;

        hr = swap_chain.*.lpVtbl.*.QueryInterface.?(
            swap_chain,
            &c.IID_IDXGISwapChain3,
            @ptrCast(&self.swapchain),
        );

        _ = swap_chain.*.lpVtbl.*.Release.?(swap_chain);

        if (hr < 0) return error.SwapChainQueryFailed;

        self.frame_index = self.swapchain.*.lpVtbl.*.GetCurrentBackBufferIndex.?(self.swapchain);

        self.viewport = .{
            .TopLeftX = 0,
            .TopLeftY = 0,
            .Width = 1280,
            .Height = 720,
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };

        self.scissor_rect = .{
            .left = 0,
            .top = 0,
            .right = 1280,
            .bottom = 720,
        };
    }

    fn createDescriptorHeaps(self: *DX12Renderer) !void {
        const desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = c.D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
            .NumDescriptors = 2,
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            .NodeMask = 0,
        };

        const hr = self.device.*.lpVtbl.*.CreateDescriptorHeap.?(
            self.device,
            &desc,
            &c.IID_ID3D12DescriptorHeap,
            @ptrCast(&self.descriptor_heap),
        );

        if (hr < 0) return error.DescriptorHeapCreationFailed;

        self.rtv_descriptor_size = self.device.*.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            self.device,
            c.D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
        );
    }

    fn createFrameResources(self: *DX12Renderer) !void {
        var rtv_handle = self.descriptor_heap.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(self.descriptor_heap);

        for (&self.render_targets, 0..) |*rt, i| {
            const hr = self.swapchain.*.lpVtbl.*.GetBuffer.?(
                self.swapchain,
                @intCast(i),
                &c.IID_ID3D12Resource,
                @ptrCast(rt),
            );

            if (hr < 0) return error.GetBufferFailed;

            self.device.*.lpVtbl.*.CreateRenderTargetView.?(
                self.device,
                rt.*,
                null,
                rtv_handle,
            );

            rtv_handle.ptr += self.rtv_descriptor_size;
        }
    }

    fn createCommandAllocator(self: *DX12Renderer) !void {
        const hr = self.device.*.lpVtbl.*.CreateCommandAllocator.?(
            self.device,
            c.D3D12_COMMAND_LIST_TYPE_DIRECT,
            &c.IID_ID3D12CommandAllocator,
            @ptrCast(&self.command_allocator),
        );

        if (hr < 0) return error.CommandAllocatorCreationFailed;
    }

    fn createCommandList(self: *DX12Renderer) !void {
        const hr = self.device.*.lpVtbl.*.CreateCommandList.?(
            self.device,
            0,
            c.D3D12_COMMAND_LIST_TYPE_DIRECT,
            self.command_allocator,
            null,
            &c.IID_ID3D12GraphicsCommandList,
            @ptrCast(&self.command_list),
        );

        if (hr < 0) return error.CommandListCreationFailed;

        _ = self.command_list.*.lpVtbl.*.Close.?(self.command_list);
    }

    fn createFence(self: *DX12Renderer) !void {
        const hr = self.device.*.lpVtbl.*.CreateFence.?(
            self.device,
            0,
            c.D3D12_FENCE_FLAG_NONE,
            &c.IID_ID3D12Fence,
            @ptrCast(&self.fence),
        );

        if (hr < 0) return error.FenceCreationFailed;

        self.fence_value = 1;

        self.fence_event = windows.kernel32.CreateEventW(null, 0, 0, null) orelse return error.EventCreationFailed;
    }

    fn createRootSignature(self: *DX12Renderer) !void {
        const desc = c.D3D12_ROOT_SIGNATURE_DESC{
            .NumParameters = 0,
            .pParameters = null,
            .NumStaticSamplers = 0,
            .pStaticSamplers = null,
            .Flags = c.D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT,
        };

        var signature: *c.ID3DBlob = undefined;
        var error_blob: ?*c.ID3DBlob = null;

        var hr = c.D3D12SerializeRootSignature(
            &desc,
            c.D3D_ROOT_SIGNATURE_VERSION_1,
            &signature,
            &error_blob,
        );

        if (hr < 0) {
            if (error_blob) |blob| {
                _ = blob.*.lpVtbl.*.Release.?(blob);
            }
            return error.RootSignatureSerializationFailed;
        }

        defer _ = signature.*.lpVtbl.*.Release.?(signature);

        hr = self.device.*.lpVtbl.*.CreateRootSignature.?(
            self.device,
            0,
            signature.*.lpVtbl.*.GetBufferPointer.?(signature),
            signature.*.lpVtbl.*.GetBufferSize.?(signature),
            &c.IID_ID3D12RootSignature,
            @ptrCast(&self.root_signature),
        );

        if (hr < 0) return error.RootSignatureCreationFailed;
    }

    fn waitForPreviousFrame(self: *DX12Renderer) void {
        const fence_value = self.fence_value;
        _ = self.command_queue.*.lpVtbl.*.Signal.?(self.command_queue, self.fence, fence_value);
        self.fence_value += 1;

        if (self.fence.*.lpVtbl.*.GetCompletedValue.?(self.fence) < fence_value) {
            _ = self.fence.*.lpVtbl.*.SetEventOnCompletion.?(self.fence, fence_value, self.fence_event);
            _ = windows.kernel32.WaitForSingleObject(self.fence_event, windows.INFINITE);
        }

        self.frame_index = self.swapchain.*.lpVtbl.*.GetCurrentBackBufferIndex.?(self.swapchain);
    }

    pub fn deinit(self: *DX12Renderer) void {
        self.waitForPreviousFrame();

        _ = windows.kernel32.CloseHandle(self.fence_event);

        _ = self.root_signature.*.lpVtbl.*.Release.?(self.root_signature);
        _ = self.fence.*.lpVtbl.*.Release.?(self.fence);
        _ = self.command_list.*.lpVtbl.*.Release.?(self.command_list);
        _ = self.command_allocator.*.lpVtbl.*.Release.?(self.command_allocator);

        for (self.render_targets) |rt| {
            _ = rt.*.lpVtbl.*.Release.?(rt);
        }

        _ = self.descriptor_heap.*.lpVtbl.*.Release.?(self.descriptor_heap);
        _ = self.swapchain.*.lpVtbl.*.Release.?(self.swapchain);
        _ = self.command_queue.*.lpVtbl.*.Release.?(self.command_queue);
        _ = self.device.*.lpVtbl.*.Release.?(self.device);
    }
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

const DX12Buffer = struct {
    allocator: std.mem.Allocator,
    resource: *c.ID3D12Resource,
    size: usize,
    usage: renderer.BufferUsage,
    mapped_ptr: ?*anyopaque = null,

    pub fn deinit(self: *DX12Buffer) void {
        if (self.mapped_ptr) |_| {
            self.resource.*.lpVtbl.*.Unmap.?(self.resource, 0, null);
        }
        _ = self.resource.*.lpVtbl.*.Release.?(self.resource);
        self.allocator.destroy(self);
    }

    pub fn map(self: *DX12Buffer) ![]u8 {
        if (self.mapped_ptr) |ptr| {
            return @as([*]u8, @ptrCast(ptr))[0..self.size];
        }

        const hr = self.resource.*.lpVtbl.*.Map.?(self.resource, 0, null, &self.mapped_ptr);
        if (hr < 0) return error.MappingFailed;

        return @as([*]u8, @ptrCast(self.mapped_ptr.?))[0..self.size];
    }

    pub fn unmap(self: *DX12Buffer) void {
        if (self.mapped_ptr) |_| {
            self.resource.*.lpVtbl.*.Unmap.?(self.resource, 0, null);
            self.mapped_ptr = null;
        }
    }

    pub fn write(self: *DX12Buffer, data: []const u8, offset: usize) void {
        const mapped_data = self.map() catch return;
        defer if (self.mapped_ptr == null) self.unmap();

        const write_size = @min(data.len, self.size - offset);
        @memcpy(mapped_data[offset..offset + write_size], data[0..write_size]);
    }
};

fn dx12BufferDeinit(ptr: *anyopaque) void {
    const buffer = @as(*DX12Buffer, @ptrCast(@alignCast(ptr)));
    buffer.deinit();
}

fn dx12BufferMap(ptr: *anyopaque) anyerror![]u8 {
    const buffer = @as(*DX12Buffer, @ptrCast(@alignCast(ptr)));
    return buffer.map();
}

fn dx12BufferUnmap(ptr: *anyopaque) void {
    const buffer = @as(*DX12Buffer, @ptrCast(@alignCast(ptr)));
    buffer.unmap();
}

fn dx12BufferWrite(ptr: *anyopaque, data: []const u8, offset: usize) void {
    const buffer = @as(*DX12Buffer, @ptrCast(@alignCast(ptr)));
    buffer.write(data, offset);
}

const dx12_buffer_vtable = renderer.Buffer.VTable{
    .deinit = dx12BufferDeinit,
    .map = dx12BufferMap,
    .unmap = dx12BufferUnmap,
    .write = dx12BufferWrite,
};

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));

    const heap_props = c.D3D12_HEAP_PROPERTIES{
        .Type = c.D3D12_HEAP_TYPE_UPLOAD,
        .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
        .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
        .CreationNodeMask = 1,
        .VisibleNodeMask = 1,
    };

    const buffer_desc = c.D3D12_RESOURCE_DESC{
        .Dimension = c.D3D12_RESOURCE_DIMENSION_BUFFER,
        .Alignment = 0,
        .Width = desc.size,
        .Height = 1,
        .DepthOrArraySize = 1,
        .MipLevels = 1,
        .Format = c.DXGI_FORMAT_UNKNOWN,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Layout = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
        .Flags = c.D3D12_RESOURCE_FLAG_NONE,
    };

    const dx12_buffer = try self.allocator.create(DX12Buffer);
    dx12_buffer.* = DX12Buffer{
        .allocator = self.allocator,
        .resource = undefined,
        .size = desc.size,
        .usage = desc.usage,
    };

    const hr = self.device.*.lpVtbl.*.CreateCommittedResource.?(
        self.device,
        &heap_props,
        c.D3D12_HEAP_FLAG_NONE,
        &buffer_desc,
        c.D3D12_RESOURCE_STATE_GENERIC_READ,
        null,
        &c.IID_ID3D12Resource,
        @ptrCast(&dx12_buffer.resource),
    );

    if (hr < 0) {
        self.allocator.destroy(dx12_buffer);
        return error.BufferCreationFailed;
    }

    const buffer = try self.allocator.create(renderer.Buffer);
    buffer.* = renderer.Buffer{
        .handle = dx12_buffer,
        .size = desc.size,
        .usage = desc.usage,
        .vtable = &dx12_buffer_vtable,
    };

    return buffer;
}

const DX12Texture = struct {
    allocator: std.mem.Allocator,
    resource: *c.ID3D12Resource,
    width: u32,
    height: u32,
    format: renderer.RenderTargetFormat,
    device: *c.ID3D12Device,

    pub fn deinit(self: *DX12Texture) void {
        _ = self.resource.*.lpVtbl.*.Release.?(self.resource);
        self.allocator.destroy(self);
    }

    pub fn createView(self: *DX12Texture) !*renderer.TextureView {
        const dx12_view = try self.allocator.create(DX12TextureView);
        dx12_view.* = DX12TextureView{
            .allocator = self.allocator,
            .resource = self.resource,
        };

        const view = try self.allocator.create(renderer.TextureView);
        view.* = renderer.TextureView{
            .handle = dx12_view,
            .vtable = &dx12_texture_view_vtable,
        };

        return view;
    }
};

const DX12TextureView = struct {
    allocator: std.mem.Allocator,
    resource: *c.ID3D12Resource,

    pub fn deinit(self: *DX12TextureView) void {
        self.allocator.destroy(self);
    }
};

fn dx12TextureDeinit(ptr: *anyopaque) void {
    const texture = @as(*DX12Texture, @ptrCast(@alignCast(ptr)));
    texture.deinit();
}

fn dx12TextureCreateView(ptr: *anyopaque) anyerror!*renderer.TextureView {
    const texture = @as(*DX12Texture, @ptrCast(@alignCast(ptr)));
    return texture.createView();
}

fn dx12TextureViewDeinit(ptr: *anyopaque) void {
    const view = @as(*DX12TextureView, @ptrCast(@alignCast(ptr)));
    view.deinit();
}

const dx12_texture_vtable = renderer.Texture.VTable{
    .deinit = dx12TextureDeinit,
    .create_view = dx12TextureCreateView,
};

const dx12_texture_view_vtable = renderer.TextureView.VTable{
    .deinit = dx12TextureViewDeinit,
};

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));

    const dxgi_format = switch (desc.format) {
        .rgba8 => c.DXGI_FORMAT_R8G8B8A8_UNORM,
        .rgba16f => c.DXGI_FORMAT_R16G16B16A16_FLOAT,
        .rgba32f => c.DXGI_FORMAT_R32G32B32A32_FLOAT,
        .depth24_stencil8 => c.DXGI_FORMAT_D24_UNORM_S8_UINT,
        .depth32f => c.DXGI_FORMAT_D32_FLOAT,
    };

    const heap_props = c.D3D12_HEAP_PROPERTIES{
        .Type = c.D3D12_HEAP_TYPE_DEFAULT,
        .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
        .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
        .CreationNodeMask = 1,
        .VisibleNodeMask = 1,
    };

    var resource_flags: c.D3D12_RESOURCE_FLAGS = c.D3D12_RESOURCE_FLAG_NONE;
    if (desc.usage.render_target) {
        if (desc.format == .depth24_stencil8 or desc.format == .depth32f) {
            resource_flags |= c.D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL;
        } else {
            resource_flags |= c.D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
        }
    }
    if (desc.usage.storage) {
        resource_flags |= c.D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
    }

    const texture_desc = c.D3D12_RESOURCE_DESC{
        .Dimension = c.D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        .Alignment = 0,
        .Width = desc.width,
        .Height = desc.height,
        .DepthOrArraySize = @intCast(desc.depth),
        .MipLevels = @intCast(desc.mip_levels),
        .Format = dxgi_format,
        .SampleDesc = .{ .Count = @intCast(desc.sample_count), .Quality = 0 },
        .Layout = c.D3D12_TEXTURE_LAYOUT_UNKNOWN,
        .Flags = resource_flags,
    };

    const dx12_texture = try self.allocator.create(DX12Texture);
    dx12_texture.* = DX12Texture{
        .allocator = self.allocator,
        .resource = undefined,
        .width = desc.width,
        .height = desc.height,
        .format = desc.format,
        .device = self.device,
    };

    const hr = self.device.*.lpVtbl.*.CreateCommittedResource.?(
        self.device,
        &heap_props,
        c.D3D12_HEAP_FLAG_NONE,
        &texture_desc,
        c.D3D12_RESOURCE_STATE_COMMON,
        null,
        &c.IID_ID3D12Resource,
        @ptrCast(&dx12_texture.resource),
    );

    if (hr < 0) {
        self.allocator.destroy(dx12_texture);
        return error.TextureCreationFailed;
    }

    const texture = try self.allocator.create(renderer.Texture);
    texture.* = renderer.Texture{
        .handle = dx12_texture,
        .width = desc.width,
        .height = desc.height,
        .format = desc.format,
        .vtable = &dx12_texture_vtable,
    };

    return texture;
}

const DX12Pipeline = struct {
    allocator: std.mem.Allocator,
    pipeline_state: *c.ID3D12PipelineState,
    root_signature: *c.ID3D12RootSignature,

    pub fn deinit(self: *DX12Pipeline) void {
        _ = self.pipeline_state.*.lpVtbl.*.Release.?(self.pipeline_state);
        _ = self.root_signature.*.lpVtbl.*.Release.?(self.root_signature);
        self.allocator.destroy(self);
    }
};

fn dx12PipelineDeinit(ptr: *anyopaque) void {
    const pipeline = @as(*DX12Pipeline, @ptrCast(@alignCast(ptr)));
    pipeline.deinit();
}

const dx12_pipeline_vtable = renderer.Pipeline.VTable{
    .deinit = dx12PipelineDeinit,
};

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));

    // Compile shaders
    var vs_blob: ?*c.ID3DBlob = null;
    var ps_blob: ?*c.ID3DBlob = null;
    var error_blob: ?*c.ID3DBlob = null;

    var hr = c.D3DCompile(
        desc.vertex_shader.ptr,
        desc.vertex_shader.len,
        "vertex_shader",
        null,
        null,
        "main",
        "vs_5_0",
        0,
        0,
        &vs_blob,
        &error_blob,
    );

    if (hr < 0) {
        if (error_blob) |blob| {
            _ = blob.*.lpVtbl.*.Release.?(blob);
        }
        return error.VertexShaderCompilationFailed;
    }
    defer if (vs_blob) |blob| _ = blob.*.lpVtbl.*.Release.?(blob);

    hr = c.D3DCompile(
        desc.fragment_shader.ptr,
        desc.fragment_shader.len,
        "pixel_shader",
        null,
        null,
        "main",
        "ps_5_0",
        0,
        0,
        &ps_blob,
        &error_blob,
    );

    if (hr < 0) {
        if (error_blob) |blob| {
            _ = blob.*.lpVtbl.*.Release.?(blob);
        }
        return error.FragmentShaderCompilationFailed;
    }
    defer if (ps_blob) |blob| _ = blob.*.lpVtbl.*.Release.?(blob);

    // Create input layout
    var input_elements = try self.allocator.alloc(c.D3D12_INPUT_ELEMENT_DESC, desc.vertex_layout.attributes.len);
    defer self.allocator.free(input_elements);

    for (desc.vertex_layout.attributes, 0..) |attr, i| {
        const semantic_name = "POSITION";
        const format = switch (attr.format) {
            .float32 => c.DXGI_FORMAT_R32_FLOAT,
            .float32x2 => c.DXGI_FORMAT_R32G32_FLOAT,
            .float32x3 => c.DXGI_FORMAT_R32G32B32_FLOAT,
            .float32x4 => c.DXGI_FORMAT_R32G32B32A32_FLOAT,
            .uint32 => c.DXGI_FORMAT_R32_UINT,
            .uint32x2 => c.DXGI_FORMAT_R32G32_UINT,
            .uint32x3 => c.DXGI_FORMAT_R32G32B32_UINT,
            .uint32x4 => c.DXGI_FORMAT_R32G32B32A32_UINT,
            .sint32 => c.DXGI_FORMAT_R32_SINT,
            .sint32x2 => c.DXGI_FORMAT_R32G32_SINT,
            .sint32x3 => c.DXGI_FORMAT_R32G32B32_SINT,
            .sint32x4 => c.DXGI_FORMAT_R32G32B32A32_SINT,
        };

        input_elements[i] = c.D3D12_INPUT_ELEMENT_DESC{
            .SemanticName = semantic_name,
            .SemanticIndex = 0,
            .Format = format,
            .InputSlot = 0,
            .AlignedByteOffset = attr.offset,
            .InputSlotClass = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
            .InstanceDataStepRate = 0,
        };
    }

    const dx12_pipeline = try self.allocator.create(DX12Pipeline);
    dx12_pipeline.* = DX12Pipeline{
        .allocator = self.allocator,
        .pipeline_state = undefined,
        .root_signature = self.root_signature,
    };

    // Create graphics pipeline state
    const pso_desc = c.D3D12_GRAPHICS_PIPELINE_STATE_DESC{
        .pRootSignature = self.root_signature,
        .VS = .{
            .pShaderBytecode = vs_blob.?.*.lpVtbl.*.GetBufferPointer.?(vs_blob.?),
            .BytecodeLength = vs_blob.?.*.lpVtbl.*.GetBufferSize.?(vs_blob.?),
        },
        .PS = .{
            .pShaderBytecode = ps_blob.?.*.lpVtbl.*.GetBufferPointer.?(ps_blob.?),
            .BytecodeLength = ps_blob.?.*.lpVtbl.*.GetBufferSize.?(ps_blob.?),
        },
        .DS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
        .HS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
        .GS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
        .StreamOutput = std.mem.zeroes(c.D3D12_STREAM_OUTPUT_DESC),
        .BlendState = c.D3D12_BLEND_DESC{
            .AlphaToCoverageEnable = 0,
            .IndependentBlendEnable = 0,
            .RenderTarget = [_]c.D3D12_RENDER_TARGET_BLEND_DESC{
                c.D3D12_RENDER_TARGET_BLEND_DESC{
                    .BlendEnable = if (desc.blend_enabled) 1 else 0,
                    .LogicOpEnable = 0,
                    .SrcBlend = c.D3D12_BLEND_ONE,
                    .DestBlend = c.D3D12_BLEND_ZERO,
                    .BlendOp = c.D3D12_BLEND_OP_ADD,
                    .SrcBlendAlpha = c.D3D12_BLEND_ONE,
                    .DestBlendAlpha = c.D3D12_BLEND_ZERO,
                    .BlendOpAlpha = c.D3D12_BLEND_OP_ADD,
                    .LogicOp = c.D3D12_LOGIC_OP_NOOP,
                    .RenderTargetWriteMask = c.D3D12_COLOR_WRITE_ENABLE_ALL,
                },
            } ++ [_]c.D3D12_RENDER_TARGET_BLEND_DESC{std.mem.zeroes(c.D3D12_RENDER_TARGET_BLEND_DESC)} ** 7,
        },
        .SampleMask = 0xffffffff,
        .RasterizerState = c.D3D12_RASTERIZER_DESC{
            .FillMode = c.D3D12_FILL_MODE_SOLID,
            .CullMode = switch (desc.cull_mode) {
                .none => c.D3D12_CULL_MODE_NONE,
                .front => c.D3D12_CULL_MODE_FRONT,
                .back => c.D3D12_CULL_MODE_BACK,
            },
            .FrontCounterClockwise = switch (desc.front_face) {
                .counter_clockwise => 1,
                .clockwise => 0,
            },
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = 1,
            .MultisampleEnable = 0,
            .AntialiasedLineEnable = 0,
            .ForcedSampleCount = 0,
            .ConservativeRaster = c.D3D12_CONSERVATIVE_RASTERIZATION_MODE_OFF,
        },
        .DepthStencilState = c.D3D12_DEPTH_STENCIL_DESC{
            .DepthEnable = if (desc.depth_test) 1 else 0,
            .DepthWriteMask = if (desc.depth_write) c.D3D12_DEPTH_WRITE_MASK_ALL else c.D3D12_DEPTH_WRITE_MASK_ZERO,
            .DepthFunc = c.D3D12_COMPARISON_FUNC_LESS,
            .StencilEnable = 0,
            .StencilReadMask = c.D3D12_DEFAULT_STENCIL_READ_MASK,
            .StencilWriteMask = c.D3D12_DEFAULT_STENCIL_WRITE_MASK,
            .FrontFace = std.mem.zeroes(c.D3D12_DEPTH_STENCILOP_DESC),
            .BackFace = std.mem.zeroes(c.D3D12_DEPTH_STENCILOP_DESC),
        },
        .InputLayout = c.D3D12_INPUT_LAYOUT_DESC{
            .pInputElementDescs = input_elements.ptr,
            .NumElements = @intCast(input_elements.len),
        },
        .IBStripCutValue = c.D3D12_INDEX_BUFFER_STRIP_CUT_VALUE_DISABLED,
        .PrimitiveTopologyType = switch (desc.primitive_type) {
            .point_list => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT,
            .line_list, .line_strip => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
            .triangle_list, .triangle_strip => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
        },
        .NumRenderTargets = 1,
        .RTVFormats = [_]c.DXGI_FORMAT{c.DXGI_FORMAT_R8G8B8A8_UNORM} ++ [_]c.DXGI_FORMAT{c.DXGI_FORMAT_UNKNOWN} ** 7,
        .DSVFormat = c.DXGI_FORMAT_UNKNOWN,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .NodeMask = 0,
        .CachedPSO = std.mem.zeroes(c.D3D12_CACHED_PIPELINE_STATE),
        .Flags = c.D3D12_PIPELINE_STATE_FLAG_NONE,
    };

    hr = self.device.*.lpVtbl.*.CreateGraphicsPipelineState.?(
        self.device,
        &pso_desc,
        &c.IID_ID3D12PipelineState,
        @ptrCast(&dx12_pipeline.pipeline_state),
    );

    if (hr < 0) {
        self.allocator.destroy(dx12_pipeline);
        return error.PipelineCreationFailed;
    }

    const pipeline = try self.allocator.create(renderer.Pipeline);
    pipeline.* = renderer.Pipeline{
        .handle = dx12_pipeline,
        .vtable = &dx12_pipeline_vtable,
    };

    return pipeline;
}

const DX12RenderPass = struct {
    allocator: std.mem.Allocator,
    command_list: *c.ID3D12GraphicsCommandList,
    renderer: *DX12Renderer,

    pub fn end(self: *DX12RenderPass) void {
        _ = self.command_list.*.lpVtbl.*.Close.?(self.command_list);

        var command_lists = [_]*c.ID3D12CommandList{@ptrCast(self.command_list)};
        self.renderer.command_queue.*.lpVtbl.*.ExecuteCommandLists.?(self.renderer.command_queue, 1, &command_lists);

        _ = self.renderer.swapchain.*.lpVtbl.*.Present.?(self.renderer.swapchain, 1, 0);
        self.renderer.waitForPreviousFrame();

        self.allocator.destroy(self);
    }

    pub fn setPipeline(self: *DX12RenderPass, pipeline: *renderer.Pipeline) void {
        const dx12_pipeline = @as(*DX12Pipeline, @ptrCast(@alignCast(pipeline.handle)));
        self.command_list.*.lpVtbl.*.SetPipelineState.?(self.command_list, dx12_pipeline.pipeline_state);
        self.command_list.*.lpVtbl.*.SetGraphicsRootSignature.?(self.command_list, dx12_pipeline.root_signature);
    }

    pub fn setVertexBuffer(self: *DX12RenderPass, slot: u32, buffer: *renderer.Buffer) void {
        const dx12_buffer = @as(*DX12Buffer, @ptrCast(@alignCast(buffer.handle)));
        const vbv = c.D3D12_VERTEX_BUFFER_VIEW{
            .BufferLocation = dx12_buffer.resource.*.lpVtbl.*.GetGPUVirtualAddress.?(dx12_buffer.resource),
            .SizeInBytes = @intCast(dx12_buffer.size),
            .StrideInBytes = 0, // This should be calculated from vertex layout
        };
        self.command_list.*.lpVtbl.*.IASetVertexBuffers.?(self.command_list, slot, 1, &vbv);
    }

    pub fn setIndexBuffer(self: *DX12RenderPass, buffer: *renderer.Buffer, format: renderer.IndexFormat) void {
        const dx12_buffer = @as(*DX12Buffer, @ptrCast(@alignCast(buffer.handle)));
        const ibv = c.D3D12_INDEX_BUFFER_VIEW{
            .BufferLocation = dx12_buffer.resource.*.lpVtbl.*.GetGPUVirtualAddress.?(dx12_buffer.resource),
            .SizeInBytes = @intCast(dx12_buffer.size),
            .Format = switch (format) {
                .uint16 => c.DXGI_FORMAT_R16_UINT,
                .uint32 => c.DXGI_FORMAT_R32_UINT,
            },
        };
        self.command_list.*.lpVtbl.*.IASetIndexBuffer.?(self.command_list, &ibv);
    }

    pub fn draw(self: *DX12RenderPass, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.command_list.*.lpVtbl.*.DrawInstanced.?(self.command_list, vertex_count, instance_count, first_vertex, first_instance);
    }

    pub fn drawIndexed(self: *DX12RenderPass, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        _ = vertex_offset;
        self.command_list.*.lpVtbl.*.DrawIndexedInstanced.?(self.command_list, index_count, instance_count, first_index, first_instance);
    }
};

fn dx12RenderPassEnd(ptr: *anyopaque) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.end();
}

fn dx12RenderPassSetPipeline(ptr: *anyopaque, pipeline: *renderer.Pipeline) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setPipeline(pipeline);
}

fn dx12RenderPassSetVertexBuffer(ptr: *anyopaque, slot: u32, buffer: *renderer.Buffer) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setVertexBuffer(slot, buffer);
}

fn dx12RenderPassSetIndexBuffer(ptr: *anyopaque, buffer: *renderer.Buffer, format: renderer.IndexFormat) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setIndexBuffer(buffer, format);
}

fn dx12RenderPassDraw(ptr: *anyopaque, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.draw(vertex_count, instance_count, first_vertex, first_instance);
}

fn dx12RenderPassDrawIndexed(ptr: *anyopaque, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
    const render_pass = @as(*DX12RenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
}

const dx12_render_pass_vtable = renderer.RenderPass.VTable{
    .end = dx12RenderPassEnd,
    .set_pipeline = dx12RenderPassSetPipeline,
    .set_vertex_buffer = dx12RenderPassSetVertexBuffer,
    .set_index_buffer = dx12RenderPassSetIndexBuffer,
    .draw = dx12RenderPassDraw,
    .draw_indexed = dx12RenderPassDrawIndexed,
};

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));

    _ = self.command_allocator.*.lpVtbl.*.Reset.?(self.command_allocator);
    _ = self.command_list.*.lpVtbl.*.Reset.?(self.command_list, self.command_allocator, null);

    const barrier = c.D3D12_RESOURCE_BARRIER{
        .Type = c.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        .Flags = c.D3D12_RESOURCE_BARRIER_FLAG_NONE,
        .Transition = .{
            .pResource = self.render_targets[self.frame_index],
            .StateBefore = c.D3D12_RESOURCE_STATE_PRESENT,
            .StateAfter = c.D3D12_RESOURCE_STATE_RENDER_TARGET,
            .Subresource = c.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        },
    };

    self.command_list.*.lpVtbl.*.ResourceBarrier.?(self.command_list, 1, &barrier);

    var rtv_handle = self.descriptor_heap.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(self.descriptor_heap);
    rtv_handle.ptr += self.frame_index * self.rtv_descriptor_size;

    self.command_list.*.lpVtbl.*.OMSetRenderTargets.?(self.command_list, 1, &rtv_handle, 0, null);

    var clear_color = [_]f32{ 0.0, 0.2, 0.4, 1.0 };
    if (desc.color_attachments.len > 0) {
        clear_color = desc.color_attachments[0].clear_color;
    }

    self.command_list.*.lpVtbl.*.ClearRenderTargetView.?(self.command_list, rtv_handle, &clear_color, 0, null);
    self.command_list.*.lpVtbl.*.RSSetViewports.?(self.command_list, 1, &self.viewport);
    self.command_list.*.lpVtbl.*.RSSetScissorRects.?(self.command_list, 1, &self.scissor_rect);

    const dx12_render_pass = try self.allocator.create(DX12RenderPass);
    dx12_render_pass.* = DX12RenderPass{
        .allocator = self.allocator,
        .command_list = self.command_list,
        .renderer = self,
    };

    const render_pass = try self.allocator.create(renderer.RenderPass);
    render_pass.* = renderer.RenderPass{
        .handle = dx12_render_pass,
        .vtable = &dx12_render_pass_vtable,
    };

    return render_pass;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));

    _ = self.command_allocator.*.lpVtbl.*.Reset.?(self.command_allocator);
    _ = self.command_list.*.lpVtbl.*.Reset.?(self.command_list, self.command_allocator, null);

    const barrier = c.D3D12_RESOURCE_BARRIER{
        .Type = c.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        .Flags = c.D3D12_RESOURCE_BARRIER_FLAG_NONE,
        .Transition = .{
            .pResource = self.render_targets[self.frame_index],
            .StateBefore = c.D3D12_RESOURCE_STATE_PRESENT,
            .StateAfter = c.D3D12_RESOURCE_STATE_RENDER_TARGET,
            .Subresource = c.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        },
    };

    self.command_list.*.lpVtbl.*.ResourceBarrier.?(self.command_list, 1, &barrier);

    var rtv_handle = self.descriptor_heap.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(self.descriptor_heap);
    rtv_handle.ptr += self.frame_index * self.rtv_descriptor_size;

    self.command_list.*.lpVtbl.*.OMSetRenderTargets.?(self.command_list, 1, &rtv_handle, 0, null);

    const clear_color = [_]f32{ 0.0, 0.2, 0.4, 1.0 };
    self.command_list.*.lpVtbl.*.ClearRenderTargetView.?(self.command_list, rtv_handle, &clear_color, 0, null);

    const present_barrier = c.D3D12_RESOURCE_BARRIER{
        .Type = c.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        .Flags = c.D3D12_RESOURCE_BARRIER_FLAG_NONE,
        .Transition = .{
            .pResource = self.render_targets[self.frame_index],
            .StateBefore = c.D3D12_RESOURCE_STATE_RENDER_TARGET,
            .StateAfter = c.D3D12_RESOURCE_STATE_PRESENT,
            .Subresource = c.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        },
    };

    self.command_list.*.lpVtbl.*.ResourceBarrier.?(self.command_list, 1, &present_barrier);

    _ = self.command_list.*.lpVtbl.*.Close.?(self.command_list);

    var command_lists = [_]*c.ID3D12CommandList{@ptrCast(self.command_list)};
    self.command_queue.*.lpVtbl.*.ExecuteCommandLists.?(self.command_queue, 1, &command_lists);

    _ = self.swapchain.*.lpVtbl.*.Present.?(self.swapchain, 1, 0);

    self.waitForPreviousFrame();
}

fn waitIdleImpl(ptr: *anyopaque) void {
    const self = @as(*DX12Renderer, @ptrCast(@alignCast(ptr)));
    self.waitForPreviousFrame();
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
    const impl = try allocator.create(DX12Renderer);
    impl.* = try DX12Renderer.init(allocator, null);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .directx12,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}