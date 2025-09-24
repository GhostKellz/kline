# Getting Started with Kline

This guide will help you set up Kline and create your first rendering application.

## 📋 Prerequisites

- **Zig 0.16.0 or later** - [Download Zig](https://ziglang.org/download/)
- **Platform-specific graphics libraries** (optional for software rendering):
  - **Windows**: DirectX 12 SDK (usually included with Windows SDK)
  - **Linux**: Vulkan SDK (`sudo apt install vulkan-sdk` or equivalent)
  - **macOS**: Xcode Command Line Tools

## 🚀 Installation

### Option 1: Add to Existing Zig Project

```bash
# Add Kline to your Zig project
zig fetch --save https://github.com/your-org/kline/archive/refs/heads/main.tar.gz
```

Then add to your `build.zig`:

```zig
const kline = b.dependency("kline", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("kline", kline.module("kline"));
```

### Option 2: Clone and Build

```bash
git clone https://github.com/your-org/kline
cd kline
zig build
```

## 🎯 Your First Kline Application

Create a simple triangle renderer:

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create renderer - starts with software for maximum compatibility
    var renderer = try kline.createRenderer(allocator, .software);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Create vertex buffer
    const vertices = [_]f32{
         0.0,  0.5, 0.0,  1.0, 0.0, 0.0, 1.0, // Top vertex (red)
        -0.5, -0.5, 0.0,  0.0, 1.0, 0.0, 1.0, // Bottom left (green)
         0.5, -0.5, 0.0,  0.0, 0.0, 1.0, 1.0, // Bottom right (blue)
    };

    const buffer_desc = kline.renderer.BufferDescriptor{
        .size = vertices.len * @sizeOf(f32),
        .usage = .{ .vertex = true },
        .mapped_at_creation = true,
    };

    const vertex_buffer = try renderer.createBuffer(buffer_desc);
    defer vertex_buffer.deinit();

    // Upload vertex data
    const mapped_data = try vertex_buffer.map();
    defer vertex_buffer.unmap();
    @memcpy(mapped_data[0..vertices.len * @sizeOf(f32)], std.mem.sliceAsBytes(&vertices));

    // Create pipeline
    const pipeline_desc = kline.renderer.PipelineDescriptor{
        .vertex_shader =
            \\#version 450
            \\layout(location = 0) in vec3 position;
            \\layout(location = 1) in vec4 color;
            \\layout(location = 0) out vec4 vertexColor;
            \\void main() {
            \\    gl_Position = vec4(position, 1.0);
            \\    vertexColor = color;
            \\}
        ,
        .fragment_shader =
            \\#version 450
            \\layout(location = 0) in vec4 vertexColor;
            \\layout(location = 0) out vec4 fragColor;
            \\void main() {
            \\    fragColor = vertexColor;
            \\}
        ,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 },
                .{ .format = .float32x4, .offset = 12, .location = 1 },
            },
            .stride = 28,
        },
    };

    const pipeline = try renderer.createPipeline(pipeline_desc);
    defer pipeline.deinit();

    // Render loop (simplified - normally you'd have a window/event loop)
    const render_pass_desc = kline.renderer.RenderPassDescriptor{
        .color_attachments = &[_]kline.renderer.ColorAttachment{
            .{
                .view = undefined, // Would be your render target
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{ 0.0, 0.2, 0.4, 1.0 },
            },
        },
    };

    const render_pass = try renderer.beginRenderPass(render_pass_desc);
    defer render_pass.end();

    render_pass.setPipeline(pipeline);
    render_pass.setVertexBuffer(0, vertex_buffer);
    render_pass.draw(3, 1, 0, 0);

    // Present frame
    try renderer.present();

    std.debug.print("Triangle rendered successfully!\\n", .{});
}
```

## 🎨 Adding Vector Graphics

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .software);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Create vector graphics context
    var vector_ctx = try kline.VectorContext.init(allocator, renderer);
    defer vector_ctx.deinit();

    // Draw a red rectangle
    vector_ctx.setFillColor(kline.vector.Color.red);
    try vector_ctx.fillRect(50, 50, 200, 100);

    // Draw a blue circle
    var path = kline.vector.Path.init(allocator);
    defer path.deinit();

    try path.circle(.{ .x = 400, .y = 300 }, 75);
    vector_ctx.setFillColor(kline.vector.Color.blue);
    try vector_ctx.fill(&path);

    try renderer.present();
}
```

## 📝 Text Rendering Example

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .software);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Create font and text renderer
    var font = try kline.text.createFont(allocator, "arial.ttf", 24.0);
    defer font.deinit();

    var text_renderer = try kline.text.TextRenderer.init(allocator, renderer);
    defer text_renderer.deinit();

    // Render text
    try kline.text.renderSimpleText(
        &text_renderer,
        "Hello, Kline!",
        &font,
        100.0, // x position
        100.0, // y position
        400.0, // max width
        .left, // alignment
        kline.vector.Color.black,
    );

    try renderer.present();
}
```

## 🎛️ Backend Selection

Kline supports multiple rendering backends. Choose based on your platform and requirements:

```zig
// Software renderer - works everywhere, CPU-based
var renderer = try kline.createRenderer(allocator, .software);

// Vulkan - best performance on Windows/Linux
var renderer = try kline.createRenderer(allocator, .vulkan);

// DirectX 12 - best performance on Windows
var renderer = try kline.createRenderer(allocator, .directx12);

// DirectX 13 - future compatibility (currently stubbed)
var renderer = try kline.createRenderer(allocator, .directx13);
```

## 🔧 Build Configuration

### Basic Builds
```bash
# Development build with all features
zig build

# Release build optimized for speed
zig build -Doptimize=ReleaseFast

# Small binary size
zig build -Doptimize=ReleaseSmall
```

### Backend-Specific Builds
```bash
# Vulkan-only build
zig build -Dvulkan=true -Ddx12=false -Dsoftware=false

# Minimal software renderer only
zig build -Dvulkan=false -Ddx12=false -Dsoftware=true

# Windows DirectX build
zig build -Ddx12=true -Dvulkan=false
```

### Feature Control
```bash
# Disable text rendering to reduce size
zig build -Dtext=false

# Disable compute shaders
zig build -Dcompute=false

# Disable advanced memory management
zig build -Dadvanced-memory=false
```

## 🧪 Running Examples

```bash
# Run the comprehensive P1-P2 demo
zig build demo

# Run the triangle example
zig build triangle

# Run tests
zig build test
```

## 🐛 Troubleshooting

### Common Issues

**"VulkanNotAvailable" Error**
- Install Vulkan SDK on your system
- Or use software renderer: `kline.createRenderer(allocator, .software)`

**"DirectX12NotAvailable" Error**
- Ensure you're on Windows 10/11
- Or build without DirectX: `zig build -Ddx12=false`

**Compilation Errors**
- Verify Zig version: `zig version` (should be 0.16.0+)
- Clean build: `rm -rf zig-cache zig-out && zig build`

**Memory Issues**
- Check allocator usage - always pair `create` with `destroy`
- Use `defer` for cleanup: `defer resource.deinit();`

### Performance Tips

1. **Use appropriate backend**: Vulkan/DX12 for performance, software for compatibility
2. **Buffer reuse**: Create buffers once, update data as needed
3. **Batch operations**: Group similar rendering operations
4. **Profile memory**: Monitor allocator usage in debug builds

## 📚 Next Steps

- **[Architecture Overview](./architecture.md)** - Understand Kline's design
- **[API Reference](./api_reference.md)** - Complete API documentation
- **[Examples](./examples.md)** - More advanced examples
- **[Performance Guide](./performance.md)** - Optimization techniques

## 🎯 Key Concepts

- **Renderer**: Core abstraction over graphics APIs
- **Backend**: Specific graphics API implementation (Vulkan, DX12, etc.)
- **Pipeline**: Defines how vertices are processed and pixels are rendered
- **Buffer**: GPU memory for vertex data, uniforms, etc.
- **Render Pass**: A sequence of rendering operations

Ready to build something amazing with Kline! 🚀