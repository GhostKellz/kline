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