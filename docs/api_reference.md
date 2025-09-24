# Kline API Reference

Complete API documentation for Kline rendering engine.

## 📖 Table of Contents

- [Core Renderer API](#core-renderer-api)
- [Backend Types](#backend-types)
- [Resource Management](#resource-management)
- [Vector Graphics](#vector-graphics)
- [Text Rendering](#text-rendering)
- [Shader System](#shader-system)
- [Threading](#threading)
- [Memory Management](#memory-management)
- [Compute Shaders](#compute-shaders)

## 🎯 Core Renderer API

### `kline.createRenderer(allocator, backend)`

Creates a new renderer instance with the specified backend.

**Parameters:**
- `allocator: std.mem.Allocator` - Memory allocator for the renderer
- `backend: Backend` - Graphics API backend to use

**Returns:** `!*Renderer` - Pointer to renderer instance

**Example:**
```zig
var renderer = try kline.createRenderer(allocator, .vulkan);
defer {
    renderer.deinit();
    allocator.destroy(renderer);
}
```

### `Renderer`

Main rendering interface providing backend-agnostic graphics operations.

#### Methods

##### `createBuffer(desc: BufferDescriptor) !*Buffer`

Creates a GPU buffer for vertex data, uniforms, etc.

**Parameters:**
- `desc.size: usize` - Buffer size in bytes
- `desc.usage: BufferUsage` - Buffer usage flags
- `desc.mapped_at_creation: bool` - Whether to map buffer immediately

**Usage Flags:**
```zig
const BufferUsage = packed struct {
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
    storage: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    indirect: bool = false,
};
```

##### `createTexture(desc: TextureDescriptor) !*Texture`

Creates a GPU texture for images, render targets, etc.

**Parameters:**
```zig
const TextureDescriptor = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    sample_count: u32 = 1,
    format: RenderTargetFormat,
    usage: TextureUsage,
};
```

##### `createPipeline(desc: PipelineDescriptor) !*Pipeline`

Creates a rendering pipeline defining vertex processing and pixel shading.

**Parameters:**
```zig
const PipelineDescriptor = struct {
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
    // ... blend parameters
};
```

##### `beginRenderPass(desc: RenderPassDescriptor) !*RenderPass`

Begins a render pass for drawing operations.

##### `present() !void`

Presents the rendered frame to the display.

##### `waitIdle() void`

Waits for all GPU operations to complete.

## 🎨 Backend Types

### `Backend`

Enumeration of supported graphics backends:

```zig
pub const Backend = enum {
    vulkan,      // Vulkan 1.3+ (Windows, Linux, Android)
    directx12,   // DirectX 12 (Windows)
    directx13,   // DirectX 13 (Future, currently stubbed)
    metal,       // Metal 3.0+ (macOS, iOS)
    opengl_es,   // OpenGL ES 3.0+ (Cross-platform)
    software,    // Software renderer (CPU, all platforms)
};
```

### Platform Availability

| Backend | Windows | Linux | macOS | iOS | Android |
|---------|---------|--------|-------|-----|---------|
| Vulkan | ✅ | ✅ | ❌ | ❌ | ✅ |
| DirectX 12 | ✅ | ❌ | ❌ | ❌ | ❌ |
| DirectX 13 | ✅ | ❌ | ❌ | ❌ | ❌ |
| Metal | ❌ | ❌ | 🚧 | 🚧 | ❌ |
| OpenGL ES | ✅ | ✅ | ✅ | ✅ | ✅ |
| Software | ✅ | ✅ | ✅ | ✅ | ✅ |

## 📦 Resource Management

### `Buffer`

GPU buffer for storing vertex data, indices, uniforms, etc.

#### Methods

##### `map() ![]u8`
Maps buffer memory for CPU access.

##### `unmap() void`
Unmaps previously mapped buffer memory.

##### `write(data: []const u8, offset: usize) void`
Writes data to buffer at specified offset.

##### `deinit() void`
Releases buffer resources.

**Example:**
```zig
const buffer = try renderer.createBuffer(.{
    .size = 1024,
    .usage = .{ .vertex = true },
    .mapped_at_creation = true,
});
defer buffer.deinit();

const mapped_data = try buffer.map();
defer buffer.unmap();
@memcpy(mapped_data[0..vertex_data.len], vertex_data);
```

### `Texture`

GPU texture for images, render targets, depth buffers, etc.

#### Methods

##### `createView() !*TextureView`
Creates a view of the texture for rendering operations.

##### `deinit() void`
Releases texture resources.

### `Pipeline`

Rendering pipeline defining the shader stages and render state.

#### Methods

##### `deinit() void`
Releases pipeline resources.

### `RenderPass`

Active rendering context for drawing operations.

#### Methods

##### `setPipeline(pipeline: *Pipeline) void`
Binds a rendering pipeline.

##### `setVertexBuffer(slot: u32, buffer: *Buffer) void`
Binds a vertex buffer to the specified slot.

##### `setIndexBuffer(buffer: *Buffer, format: IndexFormat) void`
Binds an index buffer.

##### `draw(vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void`
Issues a draw command.

##### `drawIndexed(...) void`
Issues an indexed draw command.

##### `end() void`
Ends the render pass and submits commands.

## 🎨 Vector Graphics

### `VectorContext`

2D vector graphics rendering context.

#### Creation
```zig
var vector_ctx = try kline.VectorContext.init(allocator, renderer);
defer vector_ctx.deinit();
```

#### Methods

##### `setFillColor(color: Color) void`
Sets the current fill color for shapes.

##### `setStrokeColor(color: Color) void`
Sets the current stroke color for outlines.

##### `fillRect(x: f32, y: f32, width: f32, height: f32) !void`
Fills a rectangle with the current fill color.

##### `strokeRect(x: f32, y: f32, width: f32, height: f32, width: f32) !void`
Strokes a rectangle outline.

##### `fill(path: *Path) !void`
Fills a path with the current fill color.

##### `stroke(path: *Path, width: f32) !void`
Strokes a path with the current stroke color.

### `Path`

Vector path for complex shapes.

#### Creation
```zig
var path = kline.vector.Path.init(allocator);
defer path.deinit();
```

#### Methods

##### `moveTo(point: Point) !void`
Moves the current position without drawing.

##### `lineTo(point: Point) !void`
Draws a line to the specified point.

##### `curveTo(cp1: Point, cp2: Point, end: Point) !void`
Draws a cubic Bézier curve.

##### `quadTo(cp: Point, end: Point) !void`
Draws a quadratic Bézier curve.

##### `arc(center: Point, radius: f32, start_angle: f32, end_angle: f32) !void`
Draws an arc.

##### `circle(center: Point, radius: f32) !void`
Draws a complete circle.

##### `rect(x: f32, y: f32, width: f32, height: f32) !void`
Adds a rectangle to the path.

##### `close() !void`
Closes the current path.

### `Color`

Color representation for vector graphics.

#### Predefined Colors
```zig
pub const Color = struct {
    r: f32, g: f32, b: f32, a: f32,

    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const white = Color{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const red = Color{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const green = Color{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 1, .a = 1 };
};
```

## ✏️ Text Rendering

### `Font`

Font representation with glyph caching.

#### Creation
```zig
var font = try kline.text.createFont(allocator, "arial.ttf", 16.0);
defer font.deinit();
```

#### Methods

##### `loadGlyph(codepoint: u32) !*const Glyph`
Loads and caches a glyph for the specified Unicode codepoint.

### `TextRenderer`

High-level text rendering interface.

#### Creation
```zig
var text_renderer = try kline.text.TextRenderer.init(allocator, renderer);
defer text_renderer.deinit();
```

#### Methods

##### `renderText(layout: *const TextLayout, x: f32, y: f32, color: Color) !void`
Renders a text layout at the specified position.

### `TextLayout`

Text layout engine with multi-line support.

#### Creation
```zig
var layout = try kline.text.TextLayout.init(
    allocator,
    "Hello, World!",
    &font,
    300.0, // max width
    .left  // alignment
);
defer layout.deinit();
```

### High-Level Text Functions

##### `renderSimpleText(...) !void`
Convenient function for simple text rendering:

```zig
try kline.text.renderSimpleText(
    &text_renderer,
    "Hello, Kline!",
    &font,
    100.0, // x
    100.0, // y
    400.0, // max width
    .center, // alignment
    kline.vector.Color.black,
);
```

## 🎨 Shader System

### `ShaderManager`

Advanced shader compilation and caching system.

#### Creation
```zig
var shader_manager = try kline.shader.createShaderManager(allocator);
defer shader_manager.deinit();
```

#### Methods

##### `loadShader(source: []const u8, stage: ShaderStage, options: ShaderCompileOptions) !CompiledShader`
Compiles a shader from source code with caching.

##### `loadShaderFromFile(path: []const u8, stage: ShaderStage, options: ShaderCompileOptions) !CompiledShader`
Compiles a shader from a file.

##### `hotReloadShader(...) !CompiledShader`
Recompiles a shader for development hot-reloading.

### `ShaderCompileOptions`

Shader compilation configuration:

```zig
const ShaderCompileOptions = struct {
    source_language: ShaderLanguage = .hlsl,
    target_backend: TargetBackend,
    optimization_level: u8 = 2, // 0-3
    debug_info: bool = false,
    entry_point: []const u8 = "main",
    defines: ?std.StringHashMap([]const u8) = null,
    include_paths: ?[][]const u8 = null,
};
```

### `CompiledShader`

Compiled shader bytecode with metadata:

```zig
const CompiledShader = struct {
    bytecode: []u8,
    entry_point: []const u8,
    stage: ShaderStage,
    reflection_data: ?ShaderReflection,

    pub fn deinit(self: *CompiledShader) void;
};
```

### Shader Templates

Pre-defined shader templates for common use cases:

```zig
// Vertex shader templates
kline.shader.VertexShaderTemplate.basic_3d
kline.shader.VertexShaderTemplate.basic_2d

// Fragment shader templates
kline.shader.FragmentShaderTemplate.basic_color
kline.shader.FragmentShaderTemplate.textured
```

## 🧵 Threading

### `JobSystem`

General-purpose job scheduling system.

#### Creation
```zig
var job_system = try kline.threading.createJobSystem(allocator);
defer job_system.deinit();
```

#### Methods

##### `schedule(func: anytype, args: anytype, priority: JobPriority) !void`
Schedules a function to run on the thread pool.

##### `parallelFor(WorkItem: type, items: []WorkItem, work_func: fn(*WorkItem) void) !void`
Executes a function in parallel across an array of work items.

**Example:**
```zig
var data = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
try job_system.parallelFor(f32, &data, multiplyByTwo);
```

### `ParallelRenderSystem`

Multi-threaded rendering command generation.

#### Creation
```zig
var parallel_system = try kline.threading.createRenderSystem(allocator, 4);
defer parallel_system.deinit();
```

#### Methods

##### `beginFrame() void`
Prepares for a new frame of parallel rendering.

##### `getCommandBuffer(thread_id: u32) *RenderCommandBuffer`
Gets a command buffer for the specified thread.

##### `submitParallelWork(...) !void`
Distributes work across multiple threads with automatic synchronization.

##### `executeCommandBuffers(render_pass: *RenderPass) void`
Executes all recorded commands from all threads.

## 💾 Memory Management

### `MemoryPool`

General-purpose memory pool for frequent allocations.

#### Creation
```zig
var pool = try kline.MemoryPool.init(allocator, 4096, 64, 16);
defer pool.deinit();
```

#### Methods

##### `alloc(size: usize) ![]u8`
Allocates memory from the pool.

##### `free(memory: []u8) void`
Returns memory to the pool.

##### `getUsage() f32`
Returns current pool usage as a percentage (0.0-1.0).

### `GPUMemoryPool`

Specialized memory pool for GPU resources.

#### Creation
```zig
var gpu_pool = try kline.GPUMemoryPool.init(allocator, 1024 * 1024);
defer gpu_pool.deinit();
```

#### Methods

##### `allocate(size: usize, alignment: usize) !GPUMemoryBlock`
Allocates GPU memory with specified alignment.

##### `deallocate(block: GPUMemoryBlock) void`
Frees a GPU memory block.

## ⚡ Compute Shaders

### `ParallelFor`

GPU-accelerated parallel processing.

#### Methods

##### `map1D(func: anytype, input: []const T, output: []T) !void`
Applies a function to each element in parallel.

##### `reduce(func: anytype, input: []const T, initial: T) !T`
Reduces an array to a single value using parallel computation.

**Example:**
```zig
var parallel_for = kline.ParallelFor.init(allocator, renderer);

const data = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
var result = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };

try parallel_for.map1D(square, &data, &result);

const sum = try parallel_for.reduce(add, &result, 0.0);
```

## 🔧 Utility Functions

### `getOptimalThreadCount() u32`
Returns the optimal number of threads for the current system.

### `bufferedPrint() !void`
Prints Kline version and feature information.

## 📊 Build-Time Configuration

Access build options in your code:

```zig
const build_options = @import("build_options");

if (build_options.enable_vulkan) {
    // Vulkan-specific code
}

if (build_options.enable_text_rendering) {
    // Text rendering code
}
```

Available build options:
- `enable_vulkan: bool`
- `enable_dx12: bool`
- `enable_dx13: bool`
- `enable_metal: bool`
- `enable_opengl: bool`
- `enable_software: bool`
- `enable_text_rendering: bool`
- `enable_compute_shaders: bool`
- `enable_advanced_memory: bool`

## ❌ Error Types

### Common Error Types

```zig
// Renderer errors
error.VulkanNotAvailable
error.DirectX12NotAvailable
error.BufferCreationFailed
error.TextureCreationFailed
error.PipelineCreationFailed

// Shader errors
error.CompilationFailed
error.InvalidShaderSource
error.UnsupportedTarget

// Text rendering errors
error.FontLoadFailed
error.GlyphNotFound
error.LayoutFailed

// Threading errors
error.ThreadCreationFailed
error.JobQueueFull
error.ThreadPoolShutdown

// Memory errors
error.OutOfMemory
error.PoolExhausted
```

## 📝 Usage Patterns

### Basic Rendering Loop
```zig
// One-time setup
var renderer = try kline.createRenderer(allocator, .vulkan);
var pipeline = try renderer.createPipeline(pipeline_desc);
var buffer = try renderer.createBuffer(buffer_desc);

// Per-frame rendering
while (running) {
    const render_pass = try renderer.beginRenderPass(pass_desc);
    render_pass.setPipeline(pipeline);
    render_pass.setVertexBuffer(0, buffer);
    render_pass.draw(vertex_count, 1, 0, 0);
    render_pass.end();
    try renderer.present();
}

// Cleanup
buffer.deinit();
pipeline.deinit();
renderer.deinit();
allocator.destroy(renderer);
```

### Error Handling Pattern
```zig
const renderer = kline.createRenderer(allocator, .vulkan) catch |err| switch (err) {
    error.VulkanNotAvailable => {
        std.debug.print("Vulkan not available, falling back to software\\n", .{});
        try kline.createRenderer(allocator, .software);
    },
    else => return err,
};
```

This completes the comprehensive API reference for Kline. Each function includes detailed parameter descriptions, usage examples, and integration patterns.