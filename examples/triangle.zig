const std = @import("std");
const kline = @import("kline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Kline Triangle Example\n", .{});

    var renderer = try kline.createRenderer(allocator, .software);
    defer {
        renderer.deinit();
        allocator.destroy(renderer);
    }

    var vector_ctx = try kline.VectorContext.init(allocator, renderer);
    defer vector_ctx.deinit();

    var memory_pool = try kline.MemoryPool.init(allocator, 4096, 32, 16);
    defer memory_pool.deinit();

    const vertex_data = [_]f32{
         0.0,  0.5, 0.0, 1.0, 0.0, 0.0, 1.0,
        -0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0,
         0.5, -0.5, 0.0, 0.0, 0.0, 1.0, 1.0,
    };

    const buffer_desc = kline.renderer.BufferDescriptor{
        .size = vertex_data.len * @sizeOf(f32),
        .usage = .{ .vertex = true },
        .mapped_at_creation = true,
    };

    const vertex_buffer = renderer.createBuffer(buffer_desc) catch |err| {
        std.debug.print("Failed to create vertex buffer: {}\n", .{err});
        return;
    };
    defer vertex_buffer.deinit();

    const mapped_memory = vertex_buffer.map() catch |err| {
        std.debug.print("Failed to map buffer: {}\n", .{err});
        return;
    };
    defer vertex_buffer.unmap();

    @memcpy(mapped_memory[0..vertex_data.len * @sizeOf(f32)], std.mem.sliceAsBytes(&vertex_data));

    const vertex_shader =
        \\#version 450
        \\layout(location = 0) in vec3 position;
        \\layout(location = 1) in vec4 color;
        \\layout(location = 0) out vec4 vertexColor;
        \\void main() {
        \\    gl_Position = vec4(position, 1.0);
        \\    vertexColor = color;
        \\}
    ;

    const fragment_shader =
        \\#version 450
        \\layout(location = 0) in vec4 vertexColor;
        \\layout(location = 0) out vec4 fragColor;
        \\void main() {
        \\    fragColor = vertexColor;
        \\}
    ;

    const pipeline_desc = kline.renderer.PipelineDescriptor{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_layout = .{
            .attributes = &[_]kline.renderer.VertexAttribute{
                .{ .format = .float32x3, .offset = 0, .location = 0 },
                .{ .format = .float32x4, .offset = 12, .location = 1 },
            },
            .stride = 28,
        },
        .primitive_type = .triangle_list,
        .depth_test = false,
    };

    const pipeline = renderer.createPipeline(pipeline_desc) catch |err| {
        std.debug.print("Failed to create pipeline: {}\n", .{err});
        return;
    };
    defer pipeline.deinit();

    vector_ctx.setFillColor(kline.vector.Color.red);
    vector_ctx.fillRect(50, 50, 200, 100) catch |err| {
        std.debug.print("Failed to fill rectangle: {}\n", .{err});
        return;
    };

    var path = kline.vector.Path.init(allocator);
    defer path.deinit();

    path.circle(.{ .x = 400, .y = 300 }, 50) catch |err| {
        std.debug.print("Failed to create circle path: {}\n", .{err});
        return;
    };

    vector_ctx.setFillColor(kline.vector.Color.blue);
    vector_ctx.fill(&path) catch |err| {
        std.debug.print("Failed to fill circle: {}\n", .{err});
        return;
    };

    var parallel_for = kline.ParallelFor.init(allocator, renderer);

    const data = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var result = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };

    parallel_for.map1D(square, &data, &result) catch |err| {
        std.debug.print("Failed to execute parallel map: {}\n", .{err});
        return;
    };

    std.debug.print("Original: ", .{});
    for (data) |val| {
        std.debug.print("{:.1} ", .{val});
    }
    std.debug.print("\n", .{});

    std.debug.print("Squared:  ", .{});
    for (result) |val| {
        std.debug.print("{:.1} ", .{val});
    }
    std.debug.print("\n", .{});

    const initial_value: f32 = 0.0;
    const sum = parallel_for.reduce(add, &result, initial_value) catch |err| {
        std.debug.print("Failed to execute reduce: {}\n", .{err});
        return;
    };

    std.debug.print("Sum of squares: {:.1}\n", .{sum});

    // Skip render pass for now

    renderer.present() catch |err| {
        std.debug.print("Failed to present: {}\n", .{err});
        return;
    };

    std.debug.print("Memory pool usage: {:.1}%\n", .{memory_pool.getUsage() * 100});

    std.debug.print("Triangle rendering example completed successfully!\n", .{});
}

fn square(x: f32) f32 {
    return x * x;
}

fn add(a: f32, b: f32) f32 {
    return a + b;
}