const std = @import("std");
const renderer = @import("../renderer.zig");

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub const VulkanRenderer = struct {
    allocator: std.mem.Allocator,
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    surface: c.VkSurfaceKHR,
    swapchain: c.VkSwapchainKHR,
    swapchain_images: []c.VkImage,
    swapchain_image_views: []c.VkImageView,
    render_pass: c.VkRenderPass,
    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,
    image_available_semaphore: c.VkSemaphore,
    render_finished_semaphore: c.VkSemaphore,
    in_flight_fence: c.VkFence,

    pub fn init(allocator: std.mem.Allocator) !VulkanRenderer {
        var self: VulkanRenderer = undefined;
        self.allocator = allocator;

        try self.createInstance();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapchain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createCommandPool();
        try self.createCommandBuffers();
        try self.createSyncObjects();

        return self;
    }

    fn createInstance(self: *VulkanRenderer) !void {
        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "Kline Renderer",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "Kline",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_3,
        };

        const extensions = [_][*c]const u8{
            "VK_KHR_surface",
            "VK_KHR_swapchain",
        };

        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = extensions.len,
            .ppEnabledExtensionNames = &extensions,
        };

        const result = c.vkCreateInstance(&create_info, null, &self.instance);
        if (result != c.VK_SUCCESS) {
            return error.VulkanInstanceCreationFailed;
        }
    }

    fn pickPhysicalDevice(self: *VulkanRenderer) !void {
        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, null);

        if (device_count == 0) {
            return error.NoVulkanDevices;
        }

        const devices = try self.allocator.alloc(c.VkPhysicalDevice, device_count);
        defer self.allocator.free(devices);
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

        for (devices) |device| {
            if (self.isDeviceSuitable(device)) {
                self.physical_device = device;
                break;
            }
        }

        if (self.physical_device == null) {
            return error.NoSuitableVulkanDevice;
        }
    }

    fn isDeviceSuitable(self: *VulkanRenderer, device: c.VkPhysicalDevice) bool {
        _ = self;
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);

        return properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU or
               properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
    }

    fn findMemoryType(self: *VulkanRenderer, type_filter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
        var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &mem_properties);

        for (0..mem_properties.memoryTypeCount) |i| {
            if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
                (mem_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                return @intCast(i);
            }
        }

        return error.SuitableMemoryTypeNotFound;
    }

    fn createLogicalDevice(self: *VulkanRenderer) !void {
        const queue_priority: f32 = 1.0;

        const queue_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = 0,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        const device_features = c.VkPhysicalDeviceFeatures{};

        const device_extensions = [_][*c]const u8{
            "VK_KHR_swapchain",
        };

        const create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_create_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = device_extensions.len,
            .ppEnabledExtensionNames = &device_extensions,
            .pEnabledFeatures = &device_features,
        };

        const result = c.vkCreateDevice(self.physical_device, &create_info, null, &self.device);
        if (result != c.VK_SUCCESS) {
            return error.VulkanDeviceCreationFailed;
        }

        c.vkGetDeviceQueue(self.device, 0, 0, &self.graphics_queue);
        self.present_queue = self.graphics_queue;
    }

    fn createSwapchain(self: *VulkanRenderer) !void {
        const capabilities = self.querySwapchainSupport();
        const extent = self.chooseSwapExtent(&capabilities);

        var image_count = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount) {
            image_count = capabilities.maxImageCount;
        }

        const create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = self.surface,
            .minImageCount = image_count,
            .imageFormat = c.VK_FORMAT_B8G8R8A8_SRGB,
            .imageColorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
            .clipped = c.VK_TRUE,
            .oldSwapchain = null,
        };

        const result = c.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swapchain);
        if (result != c.VK_SUCCESS) {
            return error.SwapchainCreationFailed;
        }
    }

    fn querySwapchainSupport(self: *VulkanRenderer) c.VkSurfaceCapabilitiesKHR {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface, &capabilities);
        return capabilities;
    }

    fn chooseSwapExtent(self: *VulkanRenderer, capabilities: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        _ = self;
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        return c.VkExtent2D{
            .width = std.math.clamp(800, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(600, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };
    }

    fn createImageViews(self: *VulkanRenderer) !void {
        var image_count: u32 = 0;
        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, null);

        self.swapchain_images = try self.allocator.alloc(c.VkImage, image_count);
        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, self.swapchain_images.ptr);

        self.swapchain_image_views = try self.allocator.alloc(c.VkImageView, image_count);

        for (self.swapchain_images, 0..) |image, i| {
            const create_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = c.VK_FORMAT_B8G8R8A8_SRGB,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const result = c.vkCreateImageView(self.device, &create_info, null, &self.swapchain_image_views[i]);
            if (result != c.VK_SUCCESS) {
                return error.ImageViewCreationFailed;
            }
        }
    }

    fn createRenderPass(self: *VulkanRenderer) !void {
        const color_attachment = c.VkAttachmentDescription{
            .flags = 0,
            .format = c.VK_FORMAT_B8G8R8A8_SRGB,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const color_attachment_ref = c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass = c.VkSubpassDescription{
            .flags = 0,
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
            .pResolveAttachments = null,
            .pDepthStencilAttachment = null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
        };

        const render_pass_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .attachmentCount = 1,
            .pAttachments = &color_attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 0,
            .pDependencies = null,
        };

        const result = c.vkCreateRenderPass(self.device, &render_pass_info, null, &self.render_pass);
        if (result != c.VK_SUCCESS) {
            return error.RenderPassCreationFailed;
        }
    }

    fn createCommandPool(self: *VulkanRenderer) !void {
        const pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = 0,
        };

        const result = c.vkCreateCommandPool(self.device, &pool_info, null, &self.command_pool);
        if (result != c.VK_SUCCESS) {
            return error.CommandPoolCreationFailed;
        }
    }

    fn createCommandBuffers(self: *VulkanRenderer) !void {
        self.command_buffers = try self.allocator.alloc(c.VkCommandBuffer, self.swapchain_images.len);

        const alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.command_buffers.len),
        };

        const result = c.vkAllocateCommandBuffers(self.device, &alloc_info, self.command_buffers.ptr);
        if (result != c.VK_SUCCESS) {
            return error.CommandBufferAllocationFailed;
        }
    }

    fn createSyncObjects(self: *VulkanRenderer) !void {
        const semaphore_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        };

        const fence_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        _ = c.vkCreateSemaphore(self.device, &semaphore_info, null, &self.image_available_semaphore);
        _ = c.vkCreateSemaphore(self.device, &semaphore_info, null, &self.render_finished_semaphore);
        _ = c.vkCreateFence(self.device, &fence_info, null, &self.in_flight_fence);
    }

    fn createShaderModule(self: *VulkanRenderer, shader_code: []const u8) !c.VkShaderModule {
        const create_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shader_code.len,
            .pCode = @ptrCast(@alignCast(shader_code.ptr)),
        };

        var shader_module: c.VkShaderModule = undefined;
        const result = c.vkCreateShaderModule(self.device, &create_info, null, &shader_module);
        if (result != c.VK_SUCCESS) {
            return error.ShaderModuleCreationFailed;
        }

        return shader_module;
    }

    pub fn deinit(self: *VulkanRenderer) void {
        c.vkDeviceWaitIdle(self.device);

        c.vkDestroyFence(self.device, self.in_flight_fence, null);
        c.vkDestroySemaphore(self.device, self.render_finished_semaphore, null);
        c.vkDestroySemaphore(self.device, self.image_available_semaphore, null);

        c.vkDestroyCommandPool(self.device, self.command_pool, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);

        for (self.swapchain_image_views) |view| {
            c.vkDestroyImageView(self.device, view, null);
        }

        c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);

        self.allocator.free(self.swapchain_images);
        self.allocator.free(self.swapchain_image_views);
        self.allocator.free(self.command_buffers);
    }
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

const VulkanBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: c.VkBuffer,
    memory: c.VkDeviceMemory,
    size: usize,
    usage: renderer.BufferUsage,
    device: c.VkDevice,
    mapped_ptr: ?*anyopaque = null,

    pub fn deinit(self: *VulkanBuffer) void {
        if (self.mapped_ptr) |_| {
            c.vkUnmapMemory(self.device, self.memory);
        }
        c.vkDestroyBuffer(self.device, self.buffer, null);
        c.vkFreeMemory(self.device, self.memory, null);
        self.allocator.destroy(self);
    }

    pub fn map(self: *VulkanBuffer) ![]u8 {
        if (self.mapped_ptr) |ptr| {
            return @as([*]u8, @ptrCast(ptr))[0..self.size];
        }

        const result = c.vkMapMemory(self.device, self.memory, 0, self.size, 0, &self.mapped_ptr);
        if (result != c.VK_SUCCESS) {
            return error.MappingFailed;
        }
        return @as([*]u8, @ptrCast(self.mapped_ptr.?))[0..self.size];
    }

    pub fn unmap(self: *VulkanBuffer) void {
        if (self.mapped_ptr) |_| {
            c.vkUnmapMemory(self.device, self.memory);
            self.mapped_ptr = null;
        }
    }

    pub fn write(self: *VulkanBuffer, data: []const u8, offset: usize) void {
        const mapped_data = self.map() catch return;
        defer if (self.mapped_ptr == null) self.unmap();

        const write_size = @min(data.len, self.size - offset);
        @memcpy(mapped_data[offset..offset + write_size], data[0..write_size]);
    }
};

fn vulkanBufferDeinit(ptr: *anyopaque) void {
    const buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(ptr)));
    buffer.deinit();
}

fn vulkanBufferMap(ptr: *anyopaque) anyerror![]u8 {
    const buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(ptr)));
    return buffer.map();
}

fn vulkanBufferUnmap(ptr: *anyopaque) void {
    const buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(ptr)));
    buffer.unmap();
}

fn vulkanBufferWrite(ptr: *anyopaque, data: []const u8, offset: usize) void {
    const buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(ptr)));
    buffer.write(data, offset);
}

const vulkan_buffer_vtable = renderer.Buffer.VTable{
    .deinit = vulkanBufferDeinit,
    .map = vulkanBufferMap,
    .unmap = vulkanBufferUnmap,
    .write = vulkanBufferWrite,
};

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));

    var usage_flags: c.VkBufferUsageFlags = 0;
    if (desc.usage.vertex) usage_flags |= c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (desc.usage.index) usage_flags |= c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (desc.usage.uniform) usage_flags |= c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (desc.usage.storage) usage_flags |= c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (desc.usage.transfer_src) usage_flags |= c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (desc.usage.transfer_dst) usage_flags |= c.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (desc.usage.indirect) usage_flags |= c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;

    const buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = desc.size,
        .usage = usage_flags,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    const vk_buffer = try self.allocator.create(VulkanBuffer);
    vk_buffer.* = VulkanBuffer{
        .allocator = self.allocator,
        .buffer = undefined,
        .memory = undefined,
        .size = desc.size,
        .usage = desc.usage,
        .device = self.device,
    };

    var result = c.vkCreateBuffer(self.device, &buffer_info, null, &vk_buffer.buffer);
    if (result != c.VK_SUCCESS) {
        self.allocator.destroy(vk_buffer);
        return error.BufferCreationFailed;
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(self.device, vk_buffer.buffer, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
    };

    result = c.vkAllocateMemory(self.device, &alloc_info, null, &vk_buffer.memory);
    if (result != c.VK_SUCCESS) {
        c.vkDestroyBuffer(self.device, vk_buffer.buffer, null);
        self.allocator.destroy(vk_buffer);
        return error.MemoryAllocationFailed;
    }

    result = c.vkBindBufferMemory(self.device, vk_buffer.buffer, vk_buffer.memory, 0);
    if (result != c.VK_SUCCESS) {
        c.vkFreeMemory(self.device, vk_buffer.memory, null);
        c.vkDestroyBuffer(self.device, vk_buffer.buffer, null);
        self.allocator.destroy(vk_buffer);
        return error.BufferBindFailed;
    }

    const buffer = try self.allocator.create(renderer.Buffer);
    buffer.* = renderer.Buffer{
        .handle = vk_buffer,
        .size = desc.size,
        .usage = desc.usage,
        .vtable = &vulkan_buffer_vtable,
    };

    return buffer;
}

const VulkanTexture = struct {
    allocator: std.mem.Allocator,
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    width: u32,
    height: u32,
    format: renderer.RenderTargetFormat,
    device: c.VkDevice,

    pub fn deinit(self: *VulkanTexture) void {
        c.vkDestroyImage(self.device, self.image, null);
        c.vkFreeMemory(self.device, self.memory, null);
        self.allocator.destroy(self);
    }

    pub fn createView(self: *VulkanTexture) !*renderer.TextureView {
        const vk_format = switch (self.format) {
            .rgba8 => c.VK_FORMAT_R8G8B8A8_UNORM,
            .rgba16f => c.VK_FORMAT_R16G16B16A16_SFLOAT,
            .rgba32f => c.VK_FORMAT_R32G32B32A32_SFLOAT,
            .depth24_stencil8 => c.VK_FORMAT_D24_UNORM_S8_UINT,
            .depth32f => c.VK_FORMAT_D32_SFLOAT,
        };

        const aspect_mask = switch (self.format) {
            .depth24_stencil8 => c.VK_IMAGE_ASPECT_DEPTH_BIT | c.VK_IMAGE_ASPECT_STENCIL_BIT,
            .depth32f => c.VK_IMAGE_ASPECT_DEPTH_BIT,
            else => c.VK_IMAGE_ASPECT_COLOR_BIT,
        };

        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = self.image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = vk_format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = aspect_mask,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const vk_view = try self.allocator.create(VulkanTextureView);
        vk_view.* = VulkanTextureView{
            .allocator = self.allocator,
            .view = undefined,
            .device = self.device,
        };

        const result = c.vkCreateImageView(self.device, &view_info, null, &vk_view.view);
        if (result != c.VK_SUCCESS) {
            self.allocator.destroy(vk_view);
            return error.ImageViewCreationFailed;
        }

        const view = try self.allocator.create(renderer.TextureView);
        view.* = renderer.TextureView{
            .handle = vk_view,
            .vtable = &vulkan_texture_view_vtable,
        };

        return view;
    }
};

const VulkanTextureView = struct {
    allocator: std.mem.Allocator,
    view: c.VkImageView,
    device: c.VkDevice,

    pub fn deinit(self: *VulkanTextureView) void {
        c.vkDestroyImageView(self.device, self.view, null);
        self.allocator.destroy(self);
    }
};

fn vulkanTextureDeinit(ptr: *anyopaque) void {
    const texture = @as(*VulkanTexture, @ptrCast(@alignCast(ptr)));
    texture.deinit();
}

fn vulkanTextureCreateView(ptr: *anyopaque) anyerror!*renderer.TextureView {
    const texture = @as(*VulkanTexture, @ptrCast(@alignCast(ptr)));
    return texture.createView();
}

fn vulkanTextureViewDeinit(ptr: *anyopaque) void {
    const view = @as(*VulkanTextureView, @ptrCast(@alignCast(ptr)));
    view.deinit();
}

const vulkan_texture_vtable = renderer.Texture.VTable{
    .deinit = vulkanTextureDeinit,
    .create_view = vulkanTextureCreateView,
};

const vulkan_texture_view_vtable = renderer.TextureView.VTable{
    .deinit = vulkanTextureViewDeinit,
};

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));

    const vk_format = switch (desc.format) {
        .rgba8 => c.VK_FORMAT_R8G8B8A8_UNORM,
        .rgba16f => c.VK_FORMAT_R16G16B16A16_SFLOAT,
        .rgba32f => c.VK_FORMAT_R32G32B32A32_SFLOAT,
        .depth24_stencil8 => c.VK_FORMAT_D24_UNORM_S8_UINT,
        .depth32f => c.VK_FORMAT_D32_SFLOAT,
    };

    var usage_flags: c.VkImageUsageFlags = 0;
    if (desc.usage.sampled) usage_flags |= c.VK_IMAGE_USAGE_SAMPLED_BIT;
    if (desc.usage.storage) usage_flags |= c.VK_IMAGE_USAGE_STORAGE_BIT;
    if (desc.usage.render_target) {
        if (desc.format == .depth24_stencil8 or desc.format == .depth32f) {
            usage_flags |= c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
        } else {
            usage_flags |= c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        }
    }
    if (desc.usage.transfer_src) usage_flags |= c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (desc.usage.transfer_dst) usage_flags |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;

    const image_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = vk_format,
        .extent = .{ .width = desc.width, .height = desc.height, .depth = desc.depth },
        .mipLevels = desc.mip_levels,
        .arrayLayers = 1,
        .samples = @intCast(desc.sample_count),
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage_flags,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    };

    const vk_texture = try self.allocator.create(VulkanTexture);
    vk_texture.* = VulkanTexture{
        .allocator = self.allocator,
        .image = undefined,
        .memory = undefined,
        .width = desc.width,
        .height = desc.height,
        .format = desc.format,
        .device = self.device,
    };

    var result = c.vkCreateImage(self.device, &image_info, null, &vk_texture.image);
    if (result != c.VK_SUCCESS) {
        self.allocator.destroy(vk_texture);
        return error.ImageCreationFailed;
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(self.device, vk_texture.image, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };

    result = c.vkAllocateMemory(self.device, &alloc_info, null, &vk_texture.memory);
    if (result != c.VK_SUCCESS) {
        c.vkDestroyImage(self.device, vk_texture.image, null);
        self.allocator.destroy(vk_texture);
        return error.MemoryAllocationFailed;
    }

    result = c.vkBindImageMemory(self.device, vk_texture.image, vk_texture.memory, 0);
    if (result != c.VK_SUCCESS) {
        c.vkFreeMemory(self.device, vk_texture.memory, null);
        c.vkDestroyImage(self.device, vk_texture.image, null);
        self.allocator.destroy(vk_texture);
        return error.ImageBindFailed;
    }

    const texture = try self.allocator.create(renderer.Texture);
    texture.* = renderer.Texture{
        .handle = vk_texture,
        .width = desc.width,
        .height = desc.height,
        .format = desc.format,
        .vtable = &vulkan_texture_vtable,
    };

    return texture;
}

const VulkanPipeline = struct {
    allocator: std.mem.Allocator,
    pipeline: c.VkPipeline,
    layout: c.VkPipelineLayout,
    device: c.VkDevice,

    pub fn deinit(self: *VulkanPipeline) void {
        c.vkDestroyPipeline(self.device, self.pipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.layout, null);
        self.allocator.destroy(self);
    }
};

fn vulkanPipelineDeinit(ptr: *anyopaque) void {
    const pipeline = @as(*VulkanPipeline, @ptrCast(@alignCast(ptr)));
    pipeline.deinit();
}

const vulkan_pipeline_vtable = renderer.Pipeline.VTable{
    .deinit = vulkanPipelineDeinit,
};

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));

    // Create shader modules
    const vert_shader_module = try self.createShaderModule(desc.vertex_shader);
    defer c.vkDestroyShaderModule(self.device, vert_shader_module, null);

    const frag_shader_module = try self.createShaderModule(desc.fragment_shader);
    defer c.vkDestroyShaderModule(self.device, frag_shader_module, null);

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_shader_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_shader_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };

    // Convert vertex attributes
    var vk_attributes = try self.allocator.alloc(c.VkVertexInputAttributeDescription, desc.vertex_layout.attributes.len);
    defer self.allocator.free(vk_attributes);

    for (desc.vertex_layout.attributes, 0..) |attr, i| {
        vk_attributes[i] = c.VkVertexInputAttributeDescription{
            .location = attr.location,
            .binding = 0,
            .format = switch (attr.format) {
                .float32 => c.VK_FORMAT_R32_SFLOAT,
                .float32x2 => c.VK_FORMAT_R32G32_SFLOAT,
                .float32x3 => c.VK_FORMAT_R32G32B32_SFLOAT,
                .float32x4 => c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .uint32 => c.VK_FORMAT_R32_UINT,
                .uint32x2 => c.VK_FORMAT_R32G32_UINT,
                .uint32x3 => c.VK_FORMAT_R32G32B32_UINT,
                .uint32x4 => c.VK_FORMAT_R32G32B32A32_UINT,
                .sint32 => c.VK_FORMAT_R32_SINT,
                .sint32x2 => c.VK_FORMAT_R32G32_SINT,
                .sint32x3 => c.VK_FORMAT_R32G32B32_SINT,
                .sint32x4 => c.VK_FORMAT_R32G32B32A32_SINT,
            },
            .offset = attr.offset,
        };
    }

    const binding_desc = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = desc.vertex_layout.stride,
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding_desc,
        .vertexAttributeDescriptionCount = @intCast(vk_attributes.len),
        .pVertexAttributeDescriptions = vk_attributes.ptr,
    };

    const topology = switch (desc.primitive_type) {
        .point_list => c.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        .line_list => c.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
        .line_strip => c.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
        .triangle_list => c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .triangle_strip => c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = topology,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = switch (desc.cull_mode) {
            .none => c.VK_CULL_MODE_NONE,
            .front => c.VK_CULL_MODE_FRONT_BIT,
            .back => c.VK_CULL_MODE_BACK_BIT,
        },
        .frontFace = switch (desc.front_face) {
            .counter_clockwise => c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .clockwise => c.VK_FRONT_FACE_CLOCKWISE,
        },
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    const depth_stencil = c.VkPipelineDepthStencilStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthTestEnable = if (desc.depth_test) c.VK_TRUE else c.VK_FALSE,
        .depthWriteEnable = if (desc.depth_write) c.VK_TRUE else c.VK_FALSE,
        .depthCompareOp = switch (desc.depth_compare) {
            .never => c.VK_COMPARE_OP_NEVER,
            .less => c.VK_COMPARE_OP_LESS,
            .equal => c.VK_COMPARE_OP_EQUAL,
            .less_equal => c.VK_COMPARE_OP_LESS_OR_EQUAL,
            .greater => c.VK_COMPARE_OP_GREATER,
            .not_equal => c.VK_COMPARE_OP_NOT_EQUAL,
            .greater_equal => c.VK_COMPARE_OP_GREATER_OR_EQUAL,
            .always => c.VK_COMPARE_OP_ALWAYS,
        },
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
        .front = std.mem.zeroes(c.VkStencilOpState),
        .back = std.mem.zeroes(c.VkStencilOpState),
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = if (desc.blend_enabled) c.VK_TRUE else c.VK_FALSE,
        .srcColorBlendFactor = switch (desc.blend_src_factor) {
            .zero => c.VK_BLEND_FACTOR_ZERO,
            .one => c.VK_BLEND_FACTOR_ONE,
            .src_color => c.VK_BLEND_FACTOR_SRC_COLOR,
            .one_minus_src_color => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
            .dst_color => c.VK_BLEND_FACTOR_DST_COLOR,
            .one_minus_dst_color => c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
            .src_alpha => c.VK_BLEND_FACTOR_SRC_ALPHA,
            .one_minus_src_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dst_alpha => c.VK_BLEND_FACTOR_DST_ALPHA,
            .one_minus_dst_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
        },
        .dstColorBlendFactor = switch (desc.blend_dst_factor) {
            .zero => c.VK_BLEND_FACTOR_ZERO,
            .one => c.VK_BLEND_FACTOR_ONE,
            .src_color => c.VK_BLEND_FACTOR_SRC_COLOR,
            .one_minus_src_color => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
            .dst_color => c.VK_BLEND_FACTOR_DST_COLOR,
            .one_minus_dst_color => c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
            .src_alpha => c.VK_BLEND_FACTOR_SRC_ALPHA,
            .one_minus_src_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dst_alpha => c.VK_BLEND_FACTOR_DST_ALPHA,
            .one_minus_dst_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
        },
        .colorBlendOp = switch (desc.blend_op) {
            .add => c.VK_BLEND_OP_ADD,
            .subtract => c.VK_BLEND_OP_SUBTRACT,
            .reverse_subtract => c.VK_BLEND_OP_REVERSE_SUBTRACT,
            .min => c.VK_BLEND_OP_MIN,
            .max => c.VK_BLEND_OP_MAX,
        },
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const dynamic_states = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    };

    // Create pipeline layout
    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    const vk_pipeline = try self.allocator.create(VulkanPipeline);
    vk_pipeline.* = VulkanPipeline{
        .allocator = self.allocator,
        .pipeline = undefined,
        .layout = undefined,
        .device = self.device,
    };

    var result = c.vkCreatePipelineLayout(self.device, &pipeline_layout_info, null, &vk_pipeline.layout);
    if (result != c.VK_SUCCESS) {
        self.allocator.destroy(vk_pipeline);
        return error.PipelineLayoutCreationFailed;
    }

    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = shader_stages.len,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = vk_pipeline.layout,
        .renderPass = self.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    result = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_info, null, &vk_pipeline.pipeline);
    if (result != c.VK_SUCCESS) {
        c.vkDestroyPipelineLayout(self.device, vk_pipeline.layout, null);
        self.allocator.destroy(vk_pipeline);
        return error.PipelineCreationFailed;
    }

    const pipeline = try self.allocator.create(renderer.Pipeline);
    pipeline.* = renderer.Pipeline{
        .handle = vk_pipeline,
        .vtable = &vulkan_pipeline_vtable,
    };

    return pipeline;
}

const VulkanRenderPass = struct {
    allocator: std.mem.Allocator,
    command_buffer: c.VkCommandBuffer,
    device: c.VkDevice,
    current_image_index: u32,

    pub fn end(self: *VulkanRenderPass) void {
        c.vkCmdEndRenderPass(self.command_buffer);
    }

    pub fn setPipeline(self: *VulkanRenderPass, pipeline: *renderer.Pipeline) void {
        const vk_pipeline = @as(*VulkanPipeline, @ptrCast(@alignCast(pipeline.handle)));
        c.vkCmdBindPipeline(self.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_pipeline.pipeline);
    }

    pub fn setVertexBuffer(self: *VulkanRenderPass, slot: u32, buffer: *renderer.Buffer) void {
        const vk_buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(buffer.handle)));
        const buffers = [_]c.VkBuffer{vk_buffer.buffer};
        const offsets = [_]c.VkDeviceSize{0};
        c.vkCmdBindVertexBuffers(self.command_buffer, slot, 1, &buffers, &offsets);
    }

    pub fn setIndexBuffer(self: *VulkanRenderPass, buffer: *renderer.Buffer, format: renderer.IndexFormat) void {
        const vk_buffer = @as(*VulkanBuffer, @ptrCast(@alignCast(buffer.handle)));
        const vk_format = switch (format) {
            .uint16 => c.VK_INDEX_TYPE_UINT16,
            .uint32 => c.VK_INDEX_TYPE_UINT32,
        };
        c.vkCmdBindIndexBuffer(self.command_buffer, vk_buffer.buffer, 0, vk_format);
    }

    pub fn draw(self: *VulkanRenderPass, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        c.vkCmdDraw(self.command_buffer, vertex_count, instance_count, first_vertex, first_instance);
    }

    pub fn drawIndexed(self: *VulkanRenderPass, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        c.vkCmdDrawIndexed(self.command_buffer, index_count, instance_count, first_index, vertex_offset, first_instance);
    }
};

fn vulkanRenderPassEnd(ptr: *anyopaque) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.end();
}

fn vulkanRenderPassSetPipeline(ptr: *anyopaque, pipeline: *renderer.Pipeline) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setPipeline(pipeline);
}

fn vulkanRenderPassSetVertexBuffer(ptr: *anyopaque, slot: u32, buffer: *renderer.Buffer) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setVertexBuffer(slot, buffer);
}

fn vulkanRenderPassSetIndexBuffer(ptr: *anyopaque, buffer: *renderer.Buffer, format: renderer.IndexFormat) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.setIndexBuffer(buffer, format);
}

fn vulkanRenderPassDraw(ptr: *anyopaque, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.draw(vertex_count, instance_count, first_vertex, first_instance);
}

fn vulkanRenderPassDrawIndexed(ptr: *anyopaque, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
    const render_pass = @as(*VulkanRenderPass, @ptrCast(@alignCast(ptr)));
    render_pass.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
}

const vulkan_render_pass_vtable = renderer.RenderPass.VTable{
    .end = vulkanRenderPassEnd,
    .set_pipeline = vulkanRenderPassSetPipeline,
    .set_vertex_buffer = vulkanRenderPassSetVertexBuffer,
    .set_index_buffer = vulkanRenderPassSetIndexBuffer,
    .draw = vulkanRenderPassDraw,
    .draw_indexed = vulkanRenderPassDrawIndexed,
};

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));

    _ = c.vkWaitForFences(self.device, 1, &self.in_flight_fence, c.VK_TRUE, std.math.maxInt(u64));
    _ = c.vkResetFences(self.device, 1, &self.in_flight_fence);

    var image_index: u32 = undefined;
    _ = c.vkAcquireNextImageKHR(
        self.device,
        self.swapchain,
        std.math.maxInt(u64),
        self.image_available_semaphore,
        null,
        &image_index,
    );

    _ = c.vkResetCommandBuffer(self.command_buffers[image_index], 0);

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    _ = c.vkBeginCommandBuffer(self.command_buffers[image_index], &begin_info);

    var clear_values = [_]c.VkClearValue{
        c.VkClearValue{ .color = .{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } } },
    };

    if (desc.color_attachments.len > 0) {
        const clear_color = desc.color_attachments[0].clear_color;
        clear_values[0] = c.VkClearValue{ .color = .{ .float32 = clear_color } };
    }

    const render_pass_begin = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = self.render_pass,
        .framebuffer = null,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = 800, .height = 600 },
        },
        .clearValueCount = clear_values.len,
        .pClearValues = &clear_values,
    };

    c.vkCmdBeginRenderPass(self.command_buffers[image_index], &render_pass_begin, c.VK_SUBPASS_CONTENTS_INLINE);

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = 800,
        .height = 600,
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    c.vkCmdSetViewport(self.command_buffers[image_index], 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = 800, .height = 600 },
    };
    c.vkCmdSetScissor(self.command_buffers[image_index], 0, 1, &scissor);

    const vk_render_pass = try self.allocator.create(VulkanRenderPass);
    vk_render_pass.* = VulkanRenderPass{
        .allocator = self.allocator,
        .command_buffer = self.command_buffers[image_index],
        .device = self.device,
        .current_image_index = image_index,
    };

    const render_pass = try self.allocator.create(renderer.RenderPass);
    render_pass.* = renderer.RenderPass{
        .handle = vk_render_pass,
        .vtable = &vulkan_render_pass_vtable,
    };

    return render_pass;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));

    _ = c.vkWaitForFences(self.device, 1, &self.in_flight_fence, c.VK_TRUE, std.math.maxInt(u64));
    _ = c.vkResetFences(self.device, 1, &self.in_flight_fence);

    var image_index: u32 = undefined;
    _ = c.vkAcquireNextImageKHR(
        self.device,
        self.swapchain,
        std.math.maxInt(u64),
        self.image_available_semaphore,
        null,
        &image_index,
    );

    const wait_semaphores = [_]c.VkSemaphore{self.image_available_semaphore};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signal_semaphores = [_]c.VkSemaphore{self.render_finished_semaphore};

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &self.command_buffers[image_index],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphores,
    };

    _ = c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fence);

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &self.swapchain,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    _ = c.vkQueuePresentKHR(self.present_queue, &present_info);
}

fn waitIdleImpl(ptr: *anyopaque) void {
    const self = @as(*VulkanRenderer, @ptrCast(@alignCast(ptr)));
    c.vkDeviceWaitIdle(self.device);
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
    const impl = try allocator.create(VulkanRenderer);
    impl.* = try VulkanRenderer.init(allocator);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .vulkan,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}