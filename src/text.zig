const std = @import("std");
const renderer = @import("renderer.zig");
const vector = @import("vector.zig");

pub const FontError = error{
    FontLoadFailed,
    GlyphNotFound,
    InvalidFontData,
    OutOfMemory,
};

pub const TextError = error{
    InvalidText,
    LayoutFailed,
    RenderFailed,
    OutOfMemory,
};

pub const GlyphMetrics = struct {
    width: u32,
    height: u32,
    bearing_x: i32,
    bearing_y: i32,
    advance: u32,
};

pub const Glyph = struct {
    metrics: GlyphMetrics,
    bitmap: ?[]u8 = null,
    texture: ?*renderer.Texture = null,

    pub fn deinit(self: *Glyph, allocator: std.mem.Allocator) void {
        if (self.bitmap) |bitmap| {
            allocator.free(bitmap);
        }
        if (self.texture) |texture| {
            texture.deinit();
        }
    }
};

pub const Font = struct {
    allocator: std.mem.Allocator,
    font_data: []u8,
    size: f32,
    line_height: f32,
    ascender: f32,
    descender: f32,
    glyph_cache: std.HashMap(u32, Glyph, std.hash_map.DefaultHashContext(u32), std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator, font_data: []const u8, size: f32) !Font {
        const data_copy = try allocator.dupe(u8, font_data);

        return Font{
            .allocator = allocator,
            .font_data = data_copy,
            .size = size,
            .line_height = size * 1.2, // Standard line height is typically 120% of font size
            .ascender = size * 0.8,
            .descender = size * 0.2,
            .glyph_cache = std.HashMap(u32, Glyph, std.hash_map.DefaultHashContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Font) void {
        var iterator = self.glyph_cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.glyph_cache.deinit();
        self.allocator.free(self.font_data);
    }

    pub fn loadGlyph(self: *Font, codepoint: u32) FontError!*const Glyph {
        if (self.glyph_cache.get(codepoint)) |*glyph| {
            return glyph;
        }

        // For now, create a simple rectangular glyph
        // TODO: Implement actual font parsing (TTF/OTF)
        const glyph_size = @as(u32, @intFromFloat(self.size));
        const bitmap = self.allocator.alloc(u8, glyph_size * glyph_size) catch return FontError.OutOfMemory;

        // Simple pattern for demonstration
        for (bitmap, 0..) |*pixel, i| {
            const x = i % glyph_size;
            const y = i / glyph_size;

            // Create a simple character pattern
            pixel.* = if ((x > 2 and x < glyph_size - 2) and (y > 2 and y < glyph_size - 2)) 255 else 0;
        }

        const glyph = Glyph{
            .metrics = GlyphMetrics{
                .width = glyph_size,
                .height = glyph_size,
                .bearing_x = 0,
                .bearing_y = @intFromFloat(self.ascender),
                .advance = glyph_size + 2,
            },
            .bitmap = bitmap,
        };

        try self.glyph_cache.put(codepoint, glyph);
        return self.glyph_cache.getPtr(codepoint).?;
    }
};

pub const TextAlignment = enum {
    left,
    center,
    right,
    justify,
};

pub const TextLayout = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    font: *Font,
    max_width: f32,
    alignment: TextAlignment,
    line_spacing: f32,

    // Layout results
    lines: std.ArrayList(TextLine),
    total_width: f32,
    total_height: f32,

    const TextLine = struct {
        start_index: usize,
        end_index: usize,
        width: f32,
        height: f32,
        y_offset: f32,
    };

    pub fn init(allocator: std.mem.Allocator, text: []const u8, font: *Font, max_width: f32, alignment: TextAlignment) !TextLayout {
        var layout = TextLayout{
            .allocator = allocator,
            .text = text,
            .font = font,
            .max_width = max_width,
            .alignment = alignment,
            .line_spacing = 1.0,
            .lines = std.ArrayList(TextLine).init(allocator),
            .total_width = 0,
            .total_height = 0,
        };

        try layout.performLayout();
        return layout;
    }

    pub fn deinit(self: *TextLayout) void {
        self.lines.deinit();
    }

    fn performLayout(self: *TextLayout) !void {
        var current_line_start: usize = 0;
        var current_x: f32 = 0;
        var current_y: f32 = 0;
        var line_height: f32 = self.font.line_height;

        var i: usize = 0;
        while (i < self.text.len) {
            const codepoint = self.text[i]; // Simplified - should handle UTF-8

            if (codepoint == '\n') {
                // Force line break
                try self.finalizeLine(current_line_start, i, current_x, line_height, current_y);
                current_line_start = i + 1;
                current_x = 0;
                current_y += line_height * self.line_spacing;
                i += 1;
                continue;
            }

            const glyph = self.font.loadGlyph(codepoint) catch {
                i += 1;
                continue;
            };

            const glyph_advance = @as(f32, @floatFromInt(glyph.metrics.advance));

            // Check if we need to wrap
            if (current_x + glyph_advance > self.max_width and current_x > 0) {
                // Find a good break point (simple word wrapping)
                var break_point = i;
                while (break_point > current_line_start and self.text[break_point] != ' ') {
                    break_point -= 1;
                }

                if (break_point == current_line_start) {
                    break_point = i; // Force break if no space found
                }

                try self.finalizeLine(current_line_start, break_point, current_x, line_height, current_y);
                current_line_start = break_point;
                if (break_point < self.text.len and self.text[break_point] == ' ') {
                    current_line_start += 1; // Skip the space
                }
                current_x = 0;
                current_y += line_height * self.line_spacing;
                continue;
            }

            current_x += glyph_advance;
            i += 1;
        }

        // Finalize the last line
        if (current_line_start < self.text.len) {
            try self.finalizeLine(current_line_start, self.text.len, current_x, line_height, current_y);
        }

        self.total_height = current_y + line_height;

        // Calculate total width
        for (self.lines.items) |line| {
            if (line.width > self.total_width) {
                self.total_width = line.width;
            }
        }
    }

    fn finalizeLine(self: *TextLayout, start: usize, end: usize, width: f32, height: f32, y_offset: f32) !void {
        try self.lines.append(TextLine{
            .start_index = start,
            .end_index = end,
            .width = width,
            .height = height,
            .y_offset = y_offset,
        });
    }
};

pub const TextRenderer = struct {
    allocator: std.mem.Allocator,
    renderer_ref: *renderer.Renderer,
    vector_context: *vector.VectorContext,

    pub fn init(allocator: std.mem.Allocator, renderer_ref: *renderer.Renderer) !TextRenderer {
        const vector_context = try allocator.create(vector.VectorContext);
        vector_context.* = try vector.VectorContext.init(allocator, renderer_ref);

        return TextRenderer{
            .allocator = allocator,
            .renderer_ref = renderer_ref,
            .vector_context = vector_context,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        self.vector_context.deinit();
        self.allocator.destroy(self.vector_context);
    }

    pub fn renderText(self: *TextRenderer, layout: *const TextLayout, x: f32, y: f32, color: vector.Color) TextError!void {
        for (layout.lines.items) |line| {
            var line_x = x;

            // Apply alignment
            switch (layout.alignment) {
                .left => {},
                .center => line_x += (layout.max_width - line.width) / 2,
                .right => line_x += layout.max_width - line.width,
                .justify => {
                    // TODO: Implement justify alignment
                },
            }

            const line_y = y + line.y_offset;

            for (line.start_index..line.end_index) |char_index| {
                if (char_index >= layout.text.len) break;

                const codepoint = layout.text[char_index];
                if (codepoint == ' ') {
                    const glyph = layout.font.loadGlyph(' ') catch continue;
                    line_x += @as(f32, @floatFromInt(glyph.metrics.advance));
                    continue;
                }

                const glyph = layout.font.loadGlyph(codepoint) catch continue;

                // Render glyph as a simple rectangle for now
                // TODO: Implement actual glyph bitmap rendering
                self.vector_context.setFillColor(color);
                const glyph_x = line_x + @as(f32, @floatFromInt(glyph.metrics.bearing_x));
                const glyph_y = line_y - @as(f32, @floatFromInt(glyph.metrics.bearing_y));
                const glyph_width = @as(f32, @floatFromInt(glyph.metrics.width));
                const glyph_height = @as(f32, @floatFromInt(glyph.metrics.height));

                self.vector_context.fillRect(glyph_x, glyph_y, glyph_width, glyph_height) catch return TextError.RenderFailed;

                line_x += @as(f32, @floatFromInt(glyph.metrics.advance));
            }
        }
    }

    pub fn measureText(font: *Font, text: []const u8) !struct { width: f32, height: f32 } {
        var width: f32 = 0;
        var height: f32 = font.line_height;

        for (text) |codepoint| {
            const glyph = font.loadGlyph(codepoint) catch continue;
            width += @as(f32, @floatFromInt(glyph.metrics.advance));
        }

        return .{ .width = width, .height = height };
    }
};

// High-level text rendering functions
pub fn createFont(allocator: std.mem.Allocator, font_path: []const u8, size: f32) !Font {
    // For now, create a dummy font
    // TODO: Load actual font file (TTF/OTF)
    _ = font_path;
    const dummy_data = try allocator.alloc(u8, 1024);
    @memset(dummy_data, 0);

    return Font.init(allocator, dummy_data, size);
}

pub fn renderSimpleText(
    text_renderer: *TextRenderer,
    text: []const u8,
    font: *Font,
    x: f32,
    y: f32,
    max_width: f32,
    alignment: TextAlignment,
    color: vector.Color,
) !void {
    var layout = try TextLayout.init(text_renderer.allocator, text, font, max_width, alignment);
    defer layout.deinit();

    try text_renderer.renderText(&layout, x, y, color);
}

// Test function
test "text system basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a dummy font
    var font = try createFont(allocator, "dummy.ttf", 16.0);
    defer font.deinit();

    // Test glyph loading
    const glyph = try font.loadGlyph('A');
    try std.testing.expect(glyph.metrics.width > 0);
    try std.testing.expect(glyph.metrics.height > 0);

    // Test text layout
    const text = "Hello, World!";
    var layout = try TextLayout.init(allocator, text, &font, 200.0, .left);
    defer layout.deinit();

    try std.testing.expect(layout.lines.items.len > 0);
    try std.testing.expect(layout.total_width > 0);
    try std.testing.expect(layout.total_height > 0);
}