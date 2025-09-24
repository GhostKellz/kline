# Kline Examples and Tutorials

This document provides comprehensive examples showing how to use Kline's features, from basic rendering to advanced techniques.

## 📚 Table of Contents

1. [Getting Started Examples](#getting-started-examples)
2. [Basic Rendering](#basic-rendering)
3. [Vector Graphics](#vector-graphics)
4. [Text Rendering](#text-rendering)
5. [Shader Programming](#shader-programming)
6. [Multi-threading](#multi-threading)
7. [Memory Management](#memory-management)
8. [Platform-Specific Examples](#platform-specific-examples)
9. [Integration Examples](#integration-examples)

## 🚀 Getting Started Examples

### Hello Triangle

The classic first graphics program - rendering a colored triangle:

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create renderer with best available backend
    var renderer = kline.createRenderer(allocator, .vulkan) catch |err| switch (err) {
        error.VulkanNotAvailable => try kline.createRenderer(allocator, .software),
        else => return err,
    };
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Define triangle vertices: position (xyz) + color (rgba)
    const vertices = [_]f32{
        // Top vertex (red)
         0.0,  0.5, 0.0,  1.0, 0.0, 0.0, 1.0,
        // Bottom left vertex (green)
        -0.5, -0.5, 0.0,  0.0, 1.0, 0.0, 1.0,
        // Bottom right vertex (blue)
         0.5, -0.5, 0.0,  0.0, 0.0, 1.0, 1.0,
    };

    // Create vertex buffer
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

    // Create rendering pipeline
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
        .depth_test = false,
    };

    const pipeline = try renderer.createPipeline(pipeline_desc);
    defer pipeline.deinit();

    // Render the triangle
    const render_pass_desc = kline.renderer.RenderPassDescriptor{
        .color_attachments = &[_]kline.renderer.ColorAttachment{.{
            .view = undefined, // In real app, this would be your render target
            .load_op = .clear,
            .store_op = .store,
            .clear_color = .{ 0.0, 0.1, 0.2, 1.0 }, // Dark blue background
        }},
    };

    const render_pass = try renderer.beginRenderPass(render_pass_desc);
    defer render_pass.end();

    render_pass.setPipeline(pipeline);
    render_pass.setVertexBuffer(0, vertex_buffer);
    render_pass.draw(3, 1, 0, 0); // 3 vertices, 1 instance

    // Present the frame
    try renderer.present();

    std.debug.print("Triangle rendered successfully!\\n", .{});
}
```

### Quad with Texture

Rendering a textured quadrilateral:

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .vulkan);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Quad vertices: position + UV coordinates
    const vertices = [_]f32{
        // Position    UV
        -0.5, -0.5, 0.0,  0.0, 0.0, // Bottom left
         0.5, -0.5, 0.0,  1.0, 0.0, // Bottom right
         0.5,  0.5, 0.0,  1.0, 1.0, // Top right
        -0.5,  0.5, 0.0,  0.0, 1.0, // Top left
    };

    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    // Create buffers
    const vertex_buffer = try renderer.createBuffer(.{
        .size = vertices.len * @sizeOf(f32),
        .usage = .{ .vertex = true },
        .mapped_at_creation = true,
    });
    defer vertex_buffer.deinit();

    const index_buffer = try renderer.createBuffer(.{
        .size = indices.len * @sizeOf(u16),
        .usage = .{ .index = true },
        .mapped_at_creation = true,
    });
    defer index_buffer.deinit();

    // Upload data
    {
        const vertex_data = try vertex_buffer.map();
        defer vertex_buffer.unmap();
        @memcpy(vertex_data[0..vertices.len * @sizeOf(f32)], std.mem.sliceAsBytes(&vertices));
    }

    {
        const index_data = try index_buffer.map();
        defer index_buffer.unmap();
        @memcpy(index_data[0..indices.len * @sizeOf(u16)], std.mem.sliceAsBytes(&indices));
    }

    // Create a simple checkerboard texture
    const texture_width = 256;
    const texture_height = 256;
    const texture_data = try allocator.alloc(u8, texture_width * texture_height * 4);
    defer allocator.free(texture_data);

    for (0..texture_height) |y| {
        for (0..texture_width) |x| {
            const checker = ((x / 32) + (y / 32)) % 2;
            const color: u8 = if (checker == 0) 255 else 0;
            const index = (y * texture_width + x) * 4;
            texture_data[index + 0] = color; // R
            texture_data[index + 1] = color; // G
            texture_data[index + 2] = color; // B
            texture_data[index + 3] = 255;   // A
        }
    }

    const texture = try renderer.createTexture(.{
        .width = texture_width,
        .height = texture_height,
        .format = .rgba8,
        .usage = .{ .sampled = true, .transfer_dst = true },
    });
    defer texture.deinit();

    // Upload texture data (simplified - real implementation would use staging buffer)

    // Create textured pipeline
    const pipeline = try renderer.createPipeline(.{
        .vertex_shader =
            \\#version 450
            \\layout(location = 0) in vec3 position;
            \\layout(location = 1) in vec2 uv;
            \\layout(location = 0) out vec2 fragUV;
            \\void main() {
            \\    gl_Position = vec4(position, 1.0);
            \\    fragUV = uv;
            \\}
        ,
        .fragment_shader =
            \\#version 450
            \\layout(location = 0) in vec2 fragUV;
            \\layout(location = 0) out vec4 fragColor;
            \\layout(binding = 0) uniform sampler2D texSampler;
            \\void main() {
            \\    fragColor = texture(texSampler, fragUV);
            \\}
        ,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 },
                .{ .format = .float32x2, .offset = 12, .location = 1 },
            },
            .stride = 20,
        },
    });
    defer pipeline.deinit();

    // Render
    const render_pass = try renderer.beginRenderPass(.{
        .color_attachments = &[_]kline.renderer.ColorAttachment{.{
            .view = undefined,
            .load_op = .clear,
            .store_op = .store,
            .clear_color = .{ 0.2, 0.3, 0.4, 1.0 },
        }},
    });
    defer render_pass.end();

    render_pass.setPipeline(pipeline);
    render_pass.setVertexBuffer(0, vertex_buffer);
    render_pass.setIndexBuffer(index_buffer, .uint16);
    render_pass.drawIndexed(6, 1, 0, 0, 0); // 6 indices for 2 triangles

    try renderer.present();
}
```

## 🎨 Vector Graphics

### Basic Shapes

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

    var vector_ctx = try kline.VectorContext.init(allocator, renderer);
    defer vector_ctx.deinit();

    // Draw colored rectangles
    vector_ctx.setFillColor(.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 }); // Red
    try vector_ctx.fillRect(50, 50, 100, 80);

    vector_ctx.setFillColor(.{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 0.7 }); // Semi-transparent green
    try vector_ctx.fillRect(120, 80, 100, 80);

    // Draw circles with stroke
    var circle_path = kline.vector.Path.init(allocator);
    defer circle_path.deinit();

    try circle_path.circle(.{ .x = 300, .y = 200 }, 50);
    vector_ctx.setFillColor(kline.vector.Color.blue);
    vector_ctx.setStrokeColor(kline.vector.Color.black);
    try vector_ctx.fill(&circle_path);
    try vector_ctx.stroke(&circle_path, 3.0);

    // Complex path
    var complex_path = kline.vector.Path.init(allocator);
    defer complex_path.deinit();

    try complex_path.moveTo(.{ .x = 400, .y = 100 });
    try complex_path.lineTo(.{ .x = 450, .y = 50 });
    try complex_path.curveTo(.{ .x = 500, .y = 50 }, .{ .x = 500, .y = 100 }, .{ .x = 450, .y = 100 });
    try complex_path.close();

    vector_ctx.setFillColor(.{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 }); // Orange
    try vector_ctx.fill(&complex_path);

    try renderer.present();
}
```

### Advanced Vector Graphics with Transformations

```zig
const std = @import("std");
const kline = @import("kline");

pub fn drawSpiral(vector_ctx: *kline.VectorContext, allocator: std.mem.Allocator) !void {
    var path = kline.vector.Path.init(allocator);
    defer path.deinit();

    const center_x: f32 = 300;
    const center_y: f32 = 300;
    const max_radius: f32 = 100;
    const turns: f32 = 3;
    const steps: u32 = 200;

    var first = true;
    for (0..steps) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const angle = t * turns * 2 * std.math.pi;
        const radius = t * max_radius;

        const x = center_x + @cos(angle) * radius;
        const y = center_y + @sin(angle) * radius;

        if (first) {
            try path.moveTo(.{ .x = x, .y = y });
            first = false;
        } else {
            try path.lineTo(.{ .x = x, .y = y });
        }
    }

    vector_ctx.setStrokeColor(.{ .r = 0.8, .g = 0.2, .b = 0.8, .a = 1.0 }); // Purple
    try vector_ctx.stroke(&path, 2.0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .software);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    var vector_ctx = try kline.VectorContext.init(allocator, renderer);
    defer vector_ctx.deinit();

    // Draw spiral
    try drawSpiral(&vector_ctx, allocator);

    // Draw star pattern
    var star_path = kline.vector.Path.init(allocator);
    defer star_path.deinit();

    const star_center_x: f32 = 500;
    const star_center_y: f32 = 200;
    const outer_radius: f32 = 60;
    const inner_radius: f32 = 25;
    const points: u32 = 5;

    for (0..points * 2) |i| {
        const angle = @as(f32, @floatFromInt(i)) * std.math.pi / @as(f32, @floatFromInt(points));
        const radius = if (i % 2 == 0) outer_radius else inner_radius;
        const x = star_center_x + @cos(angle) * radius;
        const y = star_center_y + @sin(angle) * radius;

        if (i == 0) {
            try star_path.moveTo(.{ .x = x, .y = y });
        } else {
            try star_path.lineTo(.{ .x = x, .y = y });
        }
    }
    try star_path.close();

    vector_ctx.setFillColor(.{ .r = 1.0, .g = 0.8, .b = 0.0, .a = 1.0 }); // Gold
    vector_ctx.setStrokeColor(.{ .r = 0.8, .g = 0.6, .b = 0.0, .a = 1.0 }); // Darker gold
    try vector_ctx.fill(&star_path);
    try vector_ctx.stroke(&star_path, 2.0);

    try renderer.present();
}
```

## ✏️ Text Rendering

### Basic Text Display

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

    // Simple text rendering
    try kline.text.renderSimpleText(
        &text_renderer,
        "Hello, Kline Graphics Engine!",
        &font,
        50.0,  // x position
        100.0, // y position
        500.0, // max width
        .left, // alignment
        kline.vector.Color.black,
    );

    // Multi-line text with different alignments
    const long_text = "This is a longer piece of text that will demonstrate " ++
                     "word wrapping and different text alignment options in " ++
                     "the Kline graphics engine.";

    try kline.text.renderSimpleText(
        &text_renderer,
        long_text,
        &font,
        50.0,
        200.0,
        400.0,
        .left,
        .{ .r = 0.2, .g = 0.2, .b = 0.8, .a = 1.0 }, // Dark blue
    );

    try kline.text.renderSimpleText(
        &text_renderer,
        long_text,
        &font,
        50.0,
        320.0,
        400.0,
        .center,
        .{ .r = 0.8, .g = 0.2, .b = 0.2, .a = 1.0 }, // Dark red
    );

    try kline.text.renderSimpleText(
        &text_renderer,
        long_text,
        &font,
        50.0,
        440.0,
        400.0,
        .right,
        .{ .r = 0.2, .g = 0.8, .b = 0.2, .a = 1.0 }, // Dark green
    );

    try renderer.present();
}
```

### Advanced Text Layout

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

    // Create multiple fonts
    var title_font = try kline.text.createFont(allocator, "arial_bold.ttf", 32.0);
    defer title_font.deinit();

    var body_font = try kline.text.createFont(allocator, "arial.ttf", 16.0);
    defer body_font.deinit();

    var caption_font = try kline.text.createFont(allocator, "arial.ttf", 12.0);
    defer caption_font.deinit();

    var text_renderer = try kline.text.TextRenderer.init(allocator, renderer);
    defer text_renderer.deinit();

    // Title
    var title_layout = try kline.text.TextLayout.init(
        allocator,
        "Kline Graphics Engine",
        &title_font,
        600.0,
        .center
    );
    defer title_layout.deinit();

    try text_renderer.renderText(&title_layout, 50.0, 50.0, kline.vector.Color.black);

    // Body text
    const body_text =
        "Kline is a powerful cross-platform rendering engine built in Zig. " ++
        "It provides hardware-accelerated 3D/4D rendering with multiple backends " ++
        "including Vulkan, DirectX 12, Metal, and a software renderer.\\n\\n" ++
        "Key features include:\\n" ++
        "• Multi-backend rendering support\\n" ++
        "• Advanced text rendering system\\n" ++
        "• Vector graphics capabilities\\n" ++
        "• Multi-threading architecture\\n" ++
        "• Advanced shader compilation";

    var body_layout = try kline.text.TextLayout.init(
        allocator,
        body_text,
        &body_font,
        500.0,
        .left
    );
    defer body_layout.deinit();

    try text_renderer.renderText(&body_layout, 50.0, 120.0,
        .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 }); // Dark gray

    // Caption
    var caption_layout = try kline.text.TextLayout.init(
        allocator,
        "Built with Zig for maximum performance and safety",
        &caption_font,
        400.0,
        .center
    );
    defer caption_layout.deinit();

    try text_renderer.renderText(&caption_layout, 100.0, 450.0,
        .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 }); // Gray

    // Measure and display text metrics
    const metrics = try kline.text.TextRenderer.measureText(&body_font, "Sample Text");
    std.debug.print("Text metrics: {d:.1}x{d:.1} pixels\\n", .{ metrics.width, metrics.height });

    try renderer.present();
}
```

## 🎨 Shader Programming

### Custom Vertex and Fragment Shaders

```zig
const std = @import("std");
const kline = @import("kline");

const vertex_shader_source =
    \\#version 450
    \\
    \\layout(location = 0) in vec3 position;
    \\layout(location = 1) in vec3 color;
    \\layout(location = 2) in vec2 uv;
    \\
    \\layout(binding = 0) uniform UniformBuffer {
    \\    mat4 mvp;
    \\    float time;
    \\} ubo;
    \\
    \\layout(location = 0) out vec3 fragColor;
    \\layout(location = 1) out vec2 fragUV;
    \\layout(location = 2) out float fragTime;
    \\
    \\void main() {
    \\    // Animate vertices with sine wave
    \\    vec3 animated_pos = position;
    \\    animated_pos.y += sin(position.x * 5.0 + ubo.time) * 0.1;
    \\
    \\    gl_Position = ubo.mvp * vec4(animated_pos, 1.0);
    \\    fragColor = color;
    \\    fragUV = uv;
    \\    fragTime = ubo.time;
    \\}
;

const fragment_shader_source =
    \\#version 450
    \\
    \\layout(location = 0) in vec3 fragColor;
    \\layout(location = 1) in vec2 fragUV;
    \\layout(location = 2) in float fragTime;
    \\
    \\layout(location = 0) out vec4 outColor;
    \\
    \\void main() {
    \\    // Animated color mixing
    \\    float pulse = sin(fragTime * 2.0) * 0.5 + 0.5;
    \\    vec3 color = mix(fragColor, vec3(fragUV, pulse), 0.3);
    \\
    \\    // Add some pattern based on UV coordinates
    \\    float pattern = sin(fragUV.x * 10.0) * sin(fragUV.y * 10.0);
    \\    color += pattern * 0.1;
    \\
    \\    outColor = vec4(color, 1.0);
    \\}
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .vulkan);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Create shader manager
    var shader_manager = try kline.shader.createShaderManager(allocator);
    defer shader_manager.deinit();

    // Compile shaders
    const compile_options = kline.shader.ShaderCompileOptions{
        .target_backend = .vulkan,
        .optimization_level = 2,
        .debug_info = false,
    };

    var vertex_shader = try shader_manager.loadShader(
        vertex_shader_source,
        .vertex,
        compile_options
    );
    defer vertex_shader.deinit();

    var fragment_shader = try shader_manager.loadShader(
        fragment_shader_source,
        .fragment,
        compile_options
    );
    defer fragment_shader.deinit();

    // Create pipeline with compiled shaders
    const pipeline = try renderer.createPipeline(.{
        .vertex_shader = vertex_shader.bytecode,
        .fragment_shader = fragment_shader.bytecode,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 }, // position
                .{ .format = .float32x3, .offset = 12, .location = 1 }, // color
                .{ .format = .float32x2, .offset = 24, .location = 2 }, // uv
            },
            .stride = 32,
        },
    });
    defer pipeline.deinit();

    // Create animated quad with vertex data
    const vertices = [_]f32{
        // Position     Color           UV
        -0.5, -0.5, 0.0,  1.0, 0.0, 0.0,  0.0, 0.0, // Bottom left - red
         0.5, -0.5, 0.0,  0.0, 1.0, 0.0,  1.0, 0.0, // Bottom right - green
         0.5,  0.5, 0.0,  0.0, 0.0, 1.0,  1.0, 1.0, // Top right - blue
        -0.5,  0.5, 0.0,  1.0, 1.0, 0.0,  0.0, 1.0, // Top left - yellow
    };

    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    // Create buffers
    const vertex_buffer = try renderer.createBuffer(.{
        .size = vertices.len * @sizeOf(f32),
        .usage = .{ .vertex = true },
        .mapped_at_creation = true,
    });
    defer vertex_buffer.deinit();

    const index_buffer = try renderer.createBuffer(.{
        .size = indices.len * @sizeOf(u16),
        .usage = .{ .index = true },
        .mapped_at_creation = true,
    });
    defer index_buffer.deinit();

    // Upload data
    vertex_buffer.write(std.mem.sliceAsBytes(&vertices), 0);
    index_buffer.write(std.mem.sliceAsBytes(&indices), 0);

    // Create uniform buffer for time animation
    const uniform_buffer = try renderer.createBuffer(.{
        .size = @sizeOf(f32) * 17, // 4x4 matrix + time float
        .usage = .{ .uniform = true },
        .mapped_at_creation = true,
    });
    defer uniform_buffer.deinit();

    // Animation loop (simplified)
    var time: f32 = 0.0;
    for (0..60) |_| { // 60 frames
        time += 0.016; // ~60 FPS

        // Update uniform buffer
        const uniform_data = [_]f32{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
            time,
        };
        uniform_buffer.write(std.mem.sliceAsBytes(&uniform_data), 0);

        // Render frame
        const render_pass = try renderer.beginRenderPass(.{
            .color_attachments = &[_]kline.renderer.ColorAttachment{.{
                .view = undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{ 0.1, 0.1, 0.2, 1.0 },
            }},
        });
        defer render_pass.end();

        render_pass.setPipeline(pipeline);
        render_pass.setVertexBuffer(0, vertex_buffer);
        render_pass.setIndexBuffer(index_buffer, .uint16);
        render_pass.drawIndexed(6, 1, 0, 0, 0);

        try renderer.present();
    }
}
```

### Hot Reloading Shaders

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var shader_manager = try kline.shader.createShaderManager(allocator);
    defer shader_manager.deinit();

    const compile_options = kline.shader.ShaderCompileOptions{
        .target_backend = .vulkan,
        .debug_info = true, // Enable debug info for development
    };

    // Load shaders from files for hot reloading
    var vertex_shader = try shader_manager.loadShaderFromFile(
        "shaders/vertex.glsl",
        .vertex,
        compile_options
    );
    defer vertex_shader.deinit();

    var fragment_shader = try shader_manager.loadShaderFromFile(
        "shaders/fragment.glsl",
        .fragment,
        compile_options
    );
    defer fragment_shader.deinit();

    // Simulate development loop with hot reloading
    var hot_reload_timer: f32 = 0;
    while (true) {
        hot_reload_timer += 0.016;

        // Check for shader file changes every second
        if (hot_reload_timer > 1.0) {
            hot_reload_timer = 0;

            // Attempt to hot-reload shaders
            if (shader_manager.hotReloadShader("shaders/vertex.glsl", .vertex, compile_options)) |new_vs| {
                vertex_shader.deinit();
                vertex_shader = new_vs;
                std.debug.print("Hot-reloaded vertex shader\\n", .{});
            } else |_| {
                // Shader compilation failed, keep using old shader
                std.debug.print("Shader compilation failed, keeping old version\\n", .{});
            }

            if (shader_manager.hotReloadShader("shaders/fragment.glsl", .fragment, compile_options)) |new_fs| {
                fragment_shader.deinit();
                fragment_shader = new_fs;
                std.debug.print("Hot-reloaded fragment shader\\n", .{});
            } else |_| {}
        }

        // Render with current shaders
        // ... rendering code

        break; // Exit loop for example
    }
}
```

## 🧵 Multi-threading

### Parallel Job Processing

```zig
const std = @import("std");
const kline = @import("kline");

const WorkItem = struct {
    input: f32,
    output: f32 = 0,

    pub fn process(self: *WorkItem) void {
        // Simulate expensive computation
        self.output = @sin(self.input) * @cos(self.input * 2) + self.input * 0.1;
        std.time.sleep(1000000); // 1ms to simulate work
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create job system
    var job_system = try kline.threading.createJobSystem(allocator);
    defer job_system.deinit();

    std.debug.print("Using {} threads\\n", .{kline.threading.getOptimalThreadCount()});

    // Create work items
    var work_items = try allocator.alloc(WorkItem, 1000);
    defer allocator.free(work_items);

    for (work_items, 0..) |*item, i| {
        item.input = @as(f32, @floatFromInt(i)) * 0.01;
    }

    // Process in parallel
    const start_time = std.time.milliTimestamp();
    try job_system.parallelFor(WorkItem, work_items, WorkItem.process);
    const end_time = std.time.milliTimestamp();

    std.debug.print("Processed {} items in {}ms\\n", .{ work_items.len, end_time - start_time });

    // Verify results
    var sum: f32 = 0;
    for (work_items) |item| {
        sum += item.output;
    }
    std.debug.print("Sum of results: {d:.3}\\n", .{sum});
}
```

### Parallel Rendering Commands

```zig
const std = @import("std");
const kline = @import("kline");

const RenderObject = struct {
    position: [3]f32,
    color: [3]f32,
    scale: f32,
};

fn renderObject(obj: *RenderObject, cmd_buffer: *kline.threading.RenderCommandBuffer) void {
    // Generate render commands for this object
    cmd_buffer.draw(36, 1, 0, 0) catch {}; // Cube has 36 vertices
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .vulkan);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Create parallel rendering system
    var parallel_system = try kline.threading.createRenderSystem(allocator, 4);
    defer parallel_system.deinit();

    // Create many render objects
    var objects = try allocator.alloc(RenderObject, 10000);
    defer allocator.free(objects);

    for (objects, 0..) |*obj, i| {
        const fi = @as(f32, @floatFromInt(i));
        obj.position = .{ @sin(fi * 0.1), @cos(fi * 0.1), fi * 0.001 };
        obj.color = .{
            @sin(fi * 0.01) * 0.5 + 0.5,
            @sin(fi * 0.02) * 0.5 + 0.5,
            @sin(fi * 0.03) * 0.5 + 0.5,
        };
        obj.scale = @sin(fi * 0.005) * 0.5 + 1.0;
    }

    // Render loop
    for (0..60) |frame| {
        std.debug.print("Frame {}\\n", .{frame});

        parallel_system.beginFrame();

        // Submit parallel work to generate render commands
        try parallel_system.submitParallelWork(RenderObject, objects, renderObject);

        // Begin actual render pass
        const render_pass = try renderer.beginRenderPass(.{
            .color_attachments = &[_]kline.renderer.ColorAttachment{.{
                .view = undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{ 0.0, 0.1, 0.2, 1.0 },
            }},
        });
        defer render_pass.end();

        // Execute all generated commands
        parallel_system.executeCommandBuffers(render_pass);

        try renderer.present();
    }

    std.debug.print("Rendered {} objects across {} frames\\n", .{ objects.len, 60 });
}
```

## 💾 Memory Management

### Custom Memory Pools

```zig
const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create different types of memory pools
    var small_object_pool = try kline.MemoryPool.init(allocator, 64 * 1024, 64, 8);
    defer small_object_pool.deinit();

    var large_object_pool = try kline.MemoryPool.init(allocator, 1024 * 1024, 4096, 16);
    defer large_object_pool.deinit();

    var gpu_pool = try kline.GPUMemoryPool.init(allocator, 256 * 1024 * 1024);
    defer gpu_pool.deinit();

    // Simulate allocation patterns
    std.debug.print("Memory Pool Performance Test\\n", .{});

    // Small frequent allocations
    const start_time = std.time.microTimestamp();

    var small_allocations = std.ArrayList([]u8).init(allocator);
    defer {
        for (small_allocations.items) |mem| {
            small_object_pool.free(mem);
        }
        small_allocations.deinit();
    }

    for (0..10000) |_| {
        const size = 32 + (std.crypto.random.int(u32) % 32); // 32-64 bytes
        const mem = try small_object_pool.alloc(size);
        try small_allocations.append(mem);
    }

    const mid_time = std.time.microTimestamp();
    std.debug.print("Small allocations: {} μs\\n", .{mid_time - start_time});

    // Large allocations
    var large_allocations = std.ArrayList([]u8).init(allocator);
    defer {
        for (large_allocations.items) |mem| {
            large_object_pool.free(mem);
        }
        large_allocations.deinit();
    }

    for (0..100) |_| {
        const size = 1024 + (std.crypto.random.int(u32) % 2048); // 1-3 KB
        const mem = try large_object_pool.alloc(size);
        try large_allocations.append(mem);
    }

    const end_time = std.time.microTimestamp();
    std.debug.print("Large allocations: {} μs\\n", .{end_time - mid_time});

    // GPU allocations
    var gpu_allocations = std.ArrayList(kline.memory_pool.GPUMemoryBlock).init(allocator);
    defer {
        for (gpu_allocations.items) |block| {
            gpu_pool.deallocate(block);
        }
        gpu_allocations.deinit();
    }

    for (0..1000) |_| {
        const size = 1024 + (std.crypto.random.int(u32) % 4096);
        const alignment = 256;
        const block = try gpu_pool.allocate(size, alignment);
        try gpu_allocations.append(block);
    }

    // Print pool usage statistics
    std.debug.print("\\nPool Usage:\\n", .{});
    std.debug.print("Small pool: {d:.1}%\\n", .{small_object_pool.getUsage() * 100});
    std.debug.print("Large pool: {d:.1}%\\n", .{large_object_pool.getUsage() * 100});
    std.debug.print("GPU pool: {d:.1}%\\n", .{gpu_pool.getUsage() * 100});
}
```

## 🖥️ Platform-Specific Examples

### Windows DirectX 12 Optimization

```zig
const std = @import("std");
const kline = @import("kline");
const builtin = @import("builtin");

pub fn main() !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("This example is Windows-specific\\n", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Force DirectX 12 backend on Windows
    var renderer = kline.createRenderer(allocator, .directx12) catch |err| switch (err) {
        error.DirectX12NotAvailable => {
            std.debug.print("DirectX 12 not available, falling back to software\\n", .{});
            try kline.createRenderer(allocator, .software);
        },
        else => return err,
    };
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    std.debug.print("Using DirectX 12 backend on Windows\\n", .{});

    // DirectX 12 specific optimizations would go here
    // - Command list batching
    // - Resource barrier optimization
    // - Descriptor heap management
    // - GPU work graphs (on supported hardware)

    // Create a high-performance rendering pipeline
    const vertices = [_]f32{
        -0.5, -0.5, 0.0,  1.0, 0.0, 0.0, 1.0,
         0.5, -0.5, 0.0,  0.0, 1.0, 0.0, 1.0,
         0.0,  0.5, 0.0,  0.0, 0.0, 1.0, 1.0,
    };

    const vertex_buffer = try renderer.createBuffer(.{
        .size = vertices.len * @sizeOf(f32),
        .usage = .{ .vertex = true },
        .mapped_at_creation = true,
    });
    defer vertex_buffer.deinit();

    vertex_buffer.write(std.mem.sliceAsBytes(&vertices), 0);

    // Use DirectX 12 optimized shader
    const dx12_pipeline = try renderer.createPipeline(.{
        .vertex_shader = kline.shader.VertexShaderTemplate.basic_2d,
        .fragment_shader = kline.shader.FragmentShaderTemplate.basic_color,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 },
                .{ .format = .float32x4, .offset = 12, .location = 1 },
            },
            .stride = 28,
        },
    });
    defer dx12_pipeline.deinit();

    // High-performance rendering loop
    const start_time = std.time.milliTimestamp();
    for (0..1000) |i| {
        const render_pass = try renderer.beginRenderPass(.{
            .color_attachments = &[_]kline.renderer.ColorAttachment{.{
                .view = undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{
                    @sin(@as(f32, @floatFromInt(i)) * 0.01) * 0.5 + 0.5,
                    0.1,
                    0.2,
                    1.0
                },
            }},
        });
        defer render_pass.end();

        render_pass.setPipeline(dx12_pipeline);
        render_pass.setVertexBuffer(0, vertex_buffer);
        render_pass.draw(3, 1, 0, 0);

        try renderer.present();
    }
    const end_time = std.time.milliTimestamp();

    std.debug.print("Rendered 1000 frames in {}ms ({d:.1} FPS)\\n",
                   .{ end_time - start_time, 1000.0 / (@as(f32, @floatFromInt(end_time - start_time)) / 1000.0) });
}
```

### Linux Vulkan with Validation Layers

```zig
const std = @import("std");
const kline = @import("kline");
const builtin = @import("builtin");

pub fn main() !void {
    if (builtin.os.tag != .linux) {
        std.debug.print("This example is Linux-specific\\n", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable Vulkan validation layers in debug builds
    if (builtin.mode == .Debug) {
        const env_map = try std.process.getEnvMap(allocator);
        defer env_map.deinit();

        try std.process.putEnv("VK_LAYER_KHRONOS_validation", "1");
        std.debug.print("Enabled Vulkan validation layers\\n", .{});
    }

    var renderer = kline.createRenderer(allocator, .vulkan) catch |err| switch (err) {
        error.VulkanNotAvailable => {
            std.debug.print("Vulkan not available, install vulkan-sdk and drivers\\n", .{});
            try kline.createRenderer(allocator, .software);
        },
        else => return err,
    };
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    std.debug.print("Using Vulkan backend on Linux\\n", .{});

    // Linux/Vulkan specific optimizations
    // - Memory type selection for different GPU vendors
    // - Optimal swapchain presentation mode
    // - Multi-queue utilization

    // Create compute shader for Linux/Vulkan
    var shader_manager = try kline.shader.createShaderManager(allocator);
    defer shader_manager.deinit();

    const compute_shader_source =
        \\#version 450
        \\layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
        \\
        \\layout(binding = 0) buffer InputBuffer {
        \\    float input_data[];
        \\};
        \\
        \\layout(binding = 1) buffer OutputBuffer {
        \\    float output_data[];
        \\};
        \\
        \\void main() {
        \\    uint index = gl_GlobalInvocationID.x;
        \\    if (index >= input_data.length()) return;
        \\
        \\    output_data[index] = sqrt(input_data[index] * input_data[index] + 1.0);
        \\}
    ;

    var compute_shader = try shader_manager.loadShader(
        compute_shader_source,
        .compute,
        .{ .target_backend = .vulkan }
    );
    defer compute_shader.deinit();

    std.debug.print("Compiled compute shader: {} bytes\\n", .{compute_shader.bytecode.len});

    // Test basic rendering
    const triangle_pipeline = try renderer.createPipeline(.{
        .vertex_shader = kline.shader.VertexShaderTemplate.basic_2d,
        .fragment_shader = kline.shader.FragmentShaderTemplate.basic_color,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 },
                .{ .format = .float32x4, .offset = 12, .location = 1 },
            },
            .stride = 28,
        },
    });
    defer triangle_pipeline.deinit();

    std.debug.print("Vulkan pipeline created successfully\\n", .{});
}
```

## 🔗 Integration Examples

### Integration with Dear ImGui

```zig
const std = @import("std");
const kline = @import("kline");
// const imgui = @import("imgui"); // Hypothetical ImGui binding

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try kline.createRenderer(allocator, .vulkan);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    // Initialize ImGui with Kline backend
    // imgui.init();
    // defer imgui.deinit();

    // imgui.createKlineBackend(renderer);
    // defer imgui.destroyKlineBackend();

    var frame_count: u32 = 0;
    while (frame_count < 100) : (frame_count += 1) {
        // ImGui frame
        // imgui.newFrame();

        // Example ImGui windows
        // if (imgui.begin("Kline Integration Demo")) {
        //     imgui.text("Frame: {}", .{frame_count});
        //     imgui.text("Backend: Vulkan");
        //     imgui.separator();
        //     if (imgui.button("Test Button")) {
        //         std.debug.print("Button clicked!\\n", .{});
        //     }
        // }
        // imgui.end();

        // Render
        const render_pass = try renderer.beginRenderPass(.{
            .color_attachments = &[_]kline.renderer.ColorAttachment{.{
                .view = undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{ 0.2, 0.3, 0.4, 1.0 },
            }},
        });
        defer render_pass.end();

        // Render your 3D scene here

        // Render ImGui
        // imgui.render();
        // imgui.renderDrawData(render_pass);

        try renderer.present();
    }
}
```

### Game Engine Integration

```zig
const std = @import("std");
const kline = @import("kline");

const GameObject = struct {
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    mesh: ?*Mesh = null,
    material: ?*Material = null,
};

const Mesh = struct {
    vertex_buffer: *kline.renderer.Buffer,
    index_buffer: *kline.renderer.Buffer,
    vertex_count: u32,
    index_count: u32,
};

const Material = struct {
    pipeline: *kline.renderer.Pipeline,
    textures: []*kline.renderer.Texture,
};

const GameEngine = struct {
    allocator: std.mem.Allocator,
    renderer: *kline.Renderer,
    shader_manager: kline.shader.ShaderManager,
    job_system: kline.threading.JobSystem,
    parallel_render_system: kline.threading.ParallelRenderSystem,

    objects: std.ArrayList(GameObject),

    pub fn init(allocator: std.mem.Allocator) !GameEngine {
        var renderer = try kline.createRenderer(allocator, .vulkan);
        var shader_manager = try kline.shader.createShaderManager(allocator);
        var job_system = try kline.threading.createJobSystem(allocator);
        var parallel_render_system = try kline.threading.createRenderSystem(allocator, 4);

        return GameEngine{
            .allocator = allocator,
            .renderer = renderer,
            .shader_manager = shader_manager,
            .job_system = job_system,
            .parallel_render_system = parallel_render_system,
            .objects = std.ArrayList(GameObject).init(allocator),
        };
    }

    pub fn deinit(self: *GameEngine) void {
        self.objects.deinit();
        self.parallel_render_system.deinit();
        self.job_system.deinit();
        self.shader_manager.deinit();
        self.renderer.deinit();
        self.allocator.destroy(self.renderer);
    }

    pub fn createCube(self: *GameEngine) !*Mesh {
        // Cube vertices and indices
        const vertices = [_]f32{
            // Front face
            -0.5, -0.5,  0.5,  0.0, 0.0,
             0.5, -0.5,  0.5,  1.0, 0.0,
             0.5,  0.5,  0.5,  1.0, 1.0,
            -0.5,  0.5,  0.5,  0.0, 1.0,
            // ... (other faces)
        };

        const indices = [_]u16{
            0, 1, 2, 2, 3, 0, // Front
            // ... (other faces)
        };

        const vertex_buffer = try self.renderer.createBuffer(.{
            .size = vertices.len * @sizeOf(f32),
            .usage = .{ .vertex = true },
            .mapped_at_creation = true,
        });
        vertex_buffer.write(std.mem.sliceAsBytes(&vertices), 0);

        const index_buffer = try self.renderer.createBuffer(.{
            .size = indices.len * @sizeOf(u16),
            .usage = .{ .index = true },
            .mapped_at_creation = true,
        });
        index_buffer.write(std.mem.sliceAsBytes(&indices), 0);

        const mesh = try self.allocator.create(Mesh);
        mesh.* = Mesh{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = vertices.len / 5, // 5 floats per vertex
            .index_count = indices.len,
        };

        return mesh;
    }

    pub fn render(self: *GameEngine, delta_time: f32) !void {
        _ = delta_time;

        // Begin parallel rendering
        self.parallel_render_system.beginFrame();

        // Submit rendering work for all objects
        try self.parallel_render_system.submitParallelWork(
            GameObject,
            self.objects.items,
            renderGameObject
        );

        // Begin actual render pass
        const render_pass = try self.renderer.beginRenderPass(.{
            .color_attachments = &[_]kline.renderer.ColorAttachment{.{
                .view = undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_color = .{ 0.1, 0.2, 0.3, 1.0 },
            }},
        });
        defer render_pass.end();

        // Execute all parallel commands
        self.parallel_render_system.executeCommandBuffers(render_pass);

        try self.renderer.present();
    }

    fn renderGameObject(obj: *GameObject, cmd_buffer: *kline.threading.RenderCommandBuffer) void {
        if (obj.mesh) |mesh| {
            if (obj.material) |material| {
                cmd_buffer.setPipeline(material.pipeline) catch {};
            }

            cmd_buffer.setBuffer(0, mesh.vertex_buffer) catch {};
            cmd_buffer.draw(mesh.vertex_count, 1, 0, 0) catch {};
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try GameEngine.init(allocator);
    defer engine.deinit();

    // Create some test objects
    const cube_mesh = try engine.createCube();

    for (0..100) |i| {
        const obj = GameObject{
            .position = .{
                @sin(@as(f32, @floatFromInt(i)) * 0.1) * 5,
                @cos(@as(f32, @floatFromInt(i)) * 0.1) * 5,
                @as(f32, @floatFromInt(i)) * 0.1 - 5
            },
            .rotation = .{ 0, 0, 0 },
            .scale = .{ 1, 1, 1 },
            .mesh = cube_mesh,
        };

        try engine.objects.append(obj);
    }

    // Game loop
    var last_time = std.time.milliTimestamp();
    for (0..300) |_| { // Run for 300 frames
        const current_time = std.time.milliTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_time)) / 1000.0;
        last_time = current_time;

        try engine.render(delta_time);
    }

    std.debug.print("Rendered {} objects for 300 frames\\n", .{engine.objects.items.len});
}
```

This comprehensive examples document covers all major aspects of using Kline, from basic triangle rendering to complex game engine integration. Each example builds upon previous concepts and demonstrates real-world usage patterns.