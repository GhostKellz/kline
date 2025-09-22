const std = @import("std");
const renderer = @import("renderer.zig");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mul(self: Vec2, scalar: f32) Vec2 {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }

    pub fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0) return self;
        return self.mul(1.0 / len);
    }

    pub fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
        return a.add(b.sub(a).mul(t));
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const white = Color{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const red = Color{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const green = Color{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 1, .a = 1 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn toU32(self: Color) u32 {
        const r = @as(u8, @intFromFloat(@min(255, self.r * 255)));
        const g = @as(u8, @intFromFloat(@min(255, self.g * 255)));
        const b = @as(u8, @intFromFloat(@min(255, self.b * 255)));
        const a = @as(u8, @intFromFloat(@min(255, self.a * 255)));
        return (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
    }

    pub fn fromU32(val: u32) Color {
        return .{
            .r = @as(f32, @floatFromInt((val >> 16) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((val >> 8) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt(val & 0xFF)) / 255.0,
            .a = @as(f32, @floatFromInt((val >> 24) & 0xFF)) / 255.0,
        };
    }

    pub fn lerp(a: Color, b: Color, t: f32) Color {
        return .{
            .r = a.r + (b.r - a.r) * t,
            .g = a.g + (b.g - a.g) * t,
            .b = a.b + (b.b - a.b) * t,
            .a = a.a + (b.a - a.a) * t,
        };
    }
};

pub const PathCommand = union(enum) {
    move_to: Vec2,
    line_to: Vec2,
    quadratic_to: struct {
        control: Vec2,
        end: Vec2,
    },
    cubic_to: struct {
        control1: Vec2,
        control2: Vec2,
        end: Vec2,
    },
    arc_to: struct {
        center: Vec2,
        radius: Vec2,
        start_angle: f32,
        end_angle: f32,
        clockwise: bool,
    },
    close,
};

pub const Path = struct {
    commands: [1024]PathCommand,
    command_count: usize,
    current_point: Vec2,

    pub fn init(allocator: std.mem.Allocator) Path {
        _ = allocator;
        return .{
            .commands = [_]PathCommand{.close} ** 1024,
            .command_count = 0,
            .current_point = .{ .x = 0, .y = 0 },
        };
    }

    pub fn deinit(self: *Path) void {
        _ = self;
    }

    pub fn moveTo(self: *Path, point: Vec2) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .{ .move_to = point };
            self.command_count += 1;
            self.current_point = point;
        } else {
            return error.PathOverflow;
        }
    }

    pub fn lineTo(self: *Path, point: Vec2) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .{ .line_to = point };
            self.command_count += 1;
            self.current_point = point;
        } else {
            return error.PathOverflow;
        }
    }

    pub fn quadraticTo(self: *Path, control: Vec2, end: Vec2) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .{
                .quadratic_to = .{
                    .control = control,
                    .end = end,
                },
            };
            self.command_count += 1;
            self.current_point = end;
        } else {
            return error.PathOverflow;
        }
    }

    pub fn cubicTo(self: *Path, control1: Vec2, control2: Vec2, end: Vec2) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .{
                .cubic_to = .{
                    .control1 = control1,
                    .control2 = control2,
                    .end = end,
                },
            };
            self.command_count += 1;
            self.current_point = end;
        } else {
            return error.PathOverflow;
        }
    }

    pub fn arcTo(self: *Path, center: Vec2, radius: Vec2, start_angle: f32, end_angle: f32, clockwise: bool) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .{
                .arc_to = .{
                    .center = center,
                    .radius = radius,
                    .start_angle = start_angle,
                    .end_angle = end_angle,
                    .clockwise = clockwise,
                },
            };
            self.command_count += 1;
            const final_angle = if (clockwise) end_angle else start_angle;
            self.current_point = .{
                .x = center.x + radius.x * @cos(final_angle),
                .y = center.y + radius.y * @sin(final_angle),
            };
        } else {
            return error.PathOverflow;
        }
    }

    pub fn close(self: *Path) !void {
        if (self.command_count < self.commands.len) {
            self.commands[self.command_count] = .close;
            self.command_count += 1;
        } else {
            return error.PathOverflow;
        }
    }

    pub fn rect(self: *Path, x: f32, y: f32, width: f32, height: f32) !void {
        try self.moveTo(.{ .x = x, .y = y });
        try self.lineTo(.{ .x = x + width, .y = y });
        try self.lineTo(.{ .x = x + width, .y = y + height });
        try self.lineTo(.{ .x = x, .y = y + height });
        try self.close();
    }

    pub fn circle(self: *Path, center: Vec2, radius: f32) !void {
        try self.arcTo(center, .{ .x = radius, .y = radius }, 0, std.math.pi * 2, true);
    }

    pub fn ellipse(self: *Path, center: Vec2, radius: Vec2) !void {
        try self.arcTo(center, radius, 0, std.math.pi * 2, true);
    }
};

pub const GradientStop = struct {
    offset: f32,
    color: Color,
};

pub const Gradient = union(enum) {
    linear: struct {
        start: Vec2,
        end: Vec2,
        stops: []const GradientStop,
    },
    radial: struct {
        center: Vec2,
        radius: f32,
        stops: []const GradientStop,
    },
};

pub const Paint = union(enum) {
    solid: Color,
    gradient: Gradient,
    pattern: struct {
        texture: *renderer.Texture,
        transform: Transform,
    },
};

pub const Transform = struct {
    m: [6]f32 = .{ 1, 0, 0, 1, 0, 0 },

    pub const identity = Transform{};

    pub fn translate(x: f32, y: f32) Transform {
        return .{ .m = .{ 1, 0, 0, 1, x, y } };
    }

    pub fn scale(sx: f32, sy: f32) Transform {
        return .{ .m = .{ sx, 0, 0, sy, 0, 0 } };
    }

    pub fn rotate(angle: f32) Transform {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .m = .{ c, s, -s, c, 0, 0 } };
    }

    pub fn mul(self: Transform, other: Transform) Transform {
        return .{
            .m = .{
                self.m[0] * other.m[0] + self.m[2] * other.m[1],
                self.m[1] * other.m[0] + self.m[3] * other.m[1],
                self.m[0] * other.m[2] + self.m[2] * other.m[3],
                self.m[1] * other.m[2] + self.m[3] * other.m[3],
                self.m[0] * other.m[4] + self.m[2] * other.m[5] + self.m[4],
                self.m[1] * other.m[4] + self.m[3] * other.m[5] + self.m[5],
            },
        };
    }

    pub fn apply(self: Transform, point: Vec2) Vec2 {
        return .{
            .x = self.m[0] * point.x + self.m[2] * point.y + self.m[4],
            .y = self.m[1] * point.x + self.m[3] * point.y + self.m[5],
        };
    }
};

pub const StrokeStyle = struct {
    width: f32 = 1.0,
    cap: LineCap = .butt,
    join: LineJoin = .miter,
    miter_limit: f32 = 10.0,
    dash_pattern: ?[]const f32 = null,
    dash_offset: f32 = 0.0,
};

pub const LineCap = enum {
    butt,
    round,
    square,
};

pub const LineJoin = enum {
    miter,
    round,
    bevel,
};

pub const BlendMode = enum {
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
};

pub const VectorContext = struct {
    renderer: *renderer.Renderer,
    allocator: std.mem.Allocator,
    transform_stack: [32]Transform,
    stack_depth: usize,
    current_transform: Transform,
    fill_paint: Paint,
    stroke_paint: Paint,
    stroke_style: StrokeStyle,
    blend_mode: BlendMode,
    global_alpha: f32,

    pub fn init(allocator: std.mem.Allocator, r: *renderer.Renderer) !VectorContext {
        return .{
            .renderer = r,
            .allocator = allocator,
            .transform_stack = [_]Transform{Transform.identity} ** 32,
            .stack_depth = 0,
            .current_transform = Transform.identity,
            .fill_paint = .{ .solid = Color.black },
            .stroke_paint = .{ .solid = Color.black },
            .stroke_style = .{},
            .blend_mode = .normal,
            .global_alpha = 1.0,
        };
    }

    pub fn deinit(self: *VectorContext) void {
        _ = self;
    }

    pub fn save(self: *VectorContext) !void {
        if (self.stack_depth < self.transform_stack.len) {
            self.transform_stack[self.stack_depth] = self.current_transform;
            self.stack_depth += 1;
        } else {
            return error.StackOverflow;
        }
    }

    pub fn restore(self: *VectorContext) void {
        if (self.stack_depth > 0) {
            self.stack_depth -= 1;
            self.current_transform = self.transform_stack[self.stack_depth];
        }
    }

    pub fn translate(self: *VectorContext, x: f32, y: f32) void {
        self.current_transform = self.current_transform.mul(Transform.translate(x, y));
    }

    pub fn scale(self: *VectorContext, sx: f32, sy: f32) void {
        self.current_transform = self.current_transform.mul(Transform.scale(sx, sy));
    }

    pub fn rotate(self: *VectorContext, angle: f32) void {
        self.current_transform = self.current_transform.mul(Transform.rotate(angle));
    }

    pub fn setFillColor(self: *VectorContext, color: Color) void {
        self.fill_paint = .{ .solid = color };
    }

    pub fn setStrokeColor(self: *VectorContext, color: Color) void {
        self.stroke_paint = .{ .solid = color };
    }

    pub fn setStrokeWidth(self: *VectorContext, width: f32) void {
        self.stroke_style.width = width;
    }

    pub fn fill(self: *VectorContext, path: *const Path) !void {
        _ = self;
        _ = path;
    }

    pub fn stroke(self: *VectorContext, path: *const Path) !void {
        _ = self;
        _ = path;
    }

    pub fn fillRect(self: *VectorContext, x: f32, y: f32, width: f32, height: f32) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.rect(x, y, width, height);
        try self.fill(&path);
    }

    pub fn strokeRect(self: *VectorContext, x: f32, y: f32, width: f32, height: f32) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.rect(x, y, width, height);
        try self.stroke(&path);
    }

    pub fn fillCircle(self: *VectorContext, center: Vec2, radius: f32) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.circle(center, radius);
        try self.fill(&path);
    }

    pub fn strokeCircle(self: *VectorContext, center: Vec2, radius: f32) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.circle(center, radius);
        try self.stroke(&path);
    }
};