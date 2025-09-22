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

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
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