const std = @import("std");
const renderer = @import("../renderer.zig");

const c = @cImport({
    @cInclude("GLES3/gl3.h");
    @cInclude("EGL/egl.h");
});

pub const GLESRenderer = struct {
    allocator: std.mem.Allocator,
    display: c.EGLDisplay,
    surface: c.EGLSurface,
    context: c.EGLContext,
    config: c.EGLConfig,
    vertex_array: c.GLuint,
    framebuffer: c.GLuint,
    renderbuffer: c.GLuint,
    depth_renderbuffer: c.GLuint,
    width: i32,
    height: i32,

    pub fn init(allocator: std.mem.Allocator) !GLESRenderer {
        var self: GLESRenderer = undefined;
        self.allocator = allocator;
        self.width = 1280;
        self.height = 720;

        try self.initEGL();
        try self.initOpenGLES();

        return self;
    }

    fn initEGL(self: *GLESRenderer) !void {
        self.display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY);
        if (self.display == c.EGL_NO_DISPLAY) {
            return error.EGLDisplayFailed;
        }

        var major: c.EGLint = undefined;
        var minor: c.EGLint = undefined;
        if (c.eglInitialize(self.display, &major, &minor) == c.EGL_FALSE) {
            return error.EGLInitializeFailed;
        }

        const config_attribs = [_]c.EGLint{
            c.EGL_SURFACE_TYPE, c.EGL_WINDOW_BIT,
            c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES3_BIT,
            c.EGL_RED_SIZE, 8,
            c.EGL_GREEN_SIZE, 8,
            c.EGL_BLUE_SIZE, 8,
            c.EGL_ALPHA_SIZE, 8,
            c.EGL_DEPTH_SIZE, 24,
            c.EGL_STENCIL_SIZE, 8,
            c.EGL_NONE,
        };

        var num_configs: c.EGLint = undefined;
        if (c.eglChooseConfig(self.display, &config_attribs, &self.config, 1, &num_configs) == c.EGL_FALSE or num_configs == 0) {
            return error.EGLConfigFailed;
        }

        const context_attribs = [_]c.EGLint{
            c.EGL_CONTEXT_CLIENT_VERSION, 3,
            c.EGL_NONE,
        };

        self.context = c.eglCreateContext(self.display, self.config, c.EGL_NO_CONTEXT, &context_attribs);
        if (self.context == c.EGL_NO_CONTEXT) {
            return error.EGLContextCreationFailed;
        }

        const pbuffer_attribs = [_]c.EGLint{
            c.EGL_WIDTH, self.width,
            c.EGL_HEIGHT, self.height,
            c.EGL_NONE,
        };

        self.surface = c.eglCreatePbufferSurface(self.display, self.config, &pbuffer_attribs);
        if (self.surface == c.EGL_NO_SURFACE) {
            return error.EGLSurfaceCreationFailed;
        }

        if (c.eglMakeCurrent(self.display, self.surface, self.surface, self.context) == c.EGL_FALSE) {
            return error.EGLMakeCurrentFailed;
        }
    }

    fn initOpenGLES(self: *GLESRenderer) !void {
        c.glGenVertexArrays(1, &self.vertex_array);
        c.glBindVertexArray(self.vertex_array);

        c.glGenFramebuffers(1, &self.framebuffer);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);

        c.glGenRenderbuffers(1, &self.renderbuffer);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, self.renderbuffer);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_RGBA8, self.width, self.height);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_RENDERBUFFER, self.renderbuffer);

        c.glGenRenderbuffers(1, &self.depth_renderbuffer);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, self.depth_renderbuffer);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH24_STENCIL8, self.width, self.height);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, self.depth_renderbuffer);

        const status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
        if (status != c.GL_FRAMEBUFFER_COMPLETE) {
            return error.FramebufferIncomplete;
        }

        c.glViewport(0, 0, self.width, self.height);
        c.glEnable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_CULL_FACE);
        c.glCullFace(c.GL_BACK);
        c.glFrontFace(c.GL_CCW);
    }

    pub fn deinit(self: *GLESRenderer) void {
        c.glDeleteRenderbuffers(1, &self.depth_renderbuffer);
        c.glDeleteRenderbuffers(1, &self.renderbuffer);
        c.glDeleteFramebuffers(1, &self.framebuffer);
        c.glDeleteVertexArrays(1, &self.vertex_array);

        _ = c.eglMakeCurrent(self.display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT);
        _ = c.eglDestroySurface(self.display, self.surface);
        _ = c.eglDestroyContext(self.display, self.context);
        _ = c.eglTerminate(self.display);
    }

    pub fn compileShader(self: *GLESRenderer, source: []const u8, shader_type: c.GLenum) !c.GLuint {
        _ = self;
        const shader = c.glCreateShader(shader_type);
        const source_ptr = source.ptr;
        const length = @as(c.GLint, @intCast(source.len));
        c.glShaderSource(shader, 1, @ptrCast(&source_ptr), &length);
        c.glCompileShader(shader);

        var success: c.GLint = undefined;
        c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
        if (success == c.GL_FALSE) {
            var info_log: [512]u8 = undefined;
            c.glGetShaderInfoLog(shader, 512, null, &info_log);
            c.glDeleteShader(shader);
            return error.ShaderCompilationFailed;
        }

        return shader;
    }

    pub fn createProgram(self: *GLESRenderer, vertex_source: []const u8, fragment_source: []const u8) !c.GLuint {
        const vertex_shader = try self.compileShader(vertex_source, c.GL_VERTEX_SHADER);
        defer c.glDeleteShader(vertex_shader);

        const fragment_shader = try self.compileShader(fragment_source, c.GL_FRAGMENT_SHADER);
        defer c.glDeleteShader(fragment_shader);

        const program = c.glCreateProgram();
        c.glAttachShader(program, vertex_shader);
        c.glAttachShader(program, fragment_shader);
        c.glLinkProgram(program);

        var success: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &success);
        if (success == c.GL_FALSE) {
            var info_log: [512]u8 = undefined;
            c.glGetProgramInfoLog(program, 512, null, &info_log);
            c.glDeleteProgram(program);
            return error.ProgramLinkingFailed;
        }

        return program;
    }
};

pub const GLESBuffer = struct {
    id: c.GLuint,
    size: usize,
    usage: renderer.BufferUsage,
    target: c.GLenum,
};

fn deinitImpl(ptr: *anyopaque) void {
    const self = @as(*GLESRenderer, @ptrCast(@alignCast(ptr)));
    self.deinit();
}

fn createBufferImpl(ptr: *anyopaque, desc: renderer.BufferDescriptor) anyerror!*renderer.Buffer {
    const self = @as(*GLESRenderer, @ptrCast(@alignCast(ptr)));

    var buffer: c.GLuint = undefined;
    c.glGenBuffers(1, &buffer);

    const target: c.GLenum = if (desc.usage.vertex)
        c.GL_ARRAY_BUFFER
    else if (desc.usage.index)
        c.GL_ELEMENT_ARRAY_BUFFER
    else if (desc.usage.uniform)
        c.GL_UNIFORM_BUFFER
    else
        c.GL_ARRAY_BUFFER;

    c.glBindBuffer(target, buffer);
    c.glBufferData(target, @intCast(desc.size), null, c.GL_DYNAMIC_DRAW);

    const gles_buffer = try self.allocator.create(GLESBuffer);
    gles_buffer.* = .{
        .id = buffer,
        .size = desc.size,
        .usage = desc.usage,
        .target = target,
    };

    const result = try self.allocator.create(renderer.Buffer);
    result.* = .{
        .handle = gles_buffer,
        .size = desc.size,
        .usage = desc.usage,
        .vtable = &buffer_vtable,
    };

    return result;
}

fn createTextureImpl(ptr: *anyopaque, desc: renderer.TextureDescriptor) anyerror!*renderer.Texture {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
}

fn createPipelineImpl(ptr: *anyopaque, desc: renderer.PipelineDescriptor) anyerror!*renderer.Pipeline {
    const self = @as(*GLESRenderer, @ptrCast(@alignCast(ptr)));
    const program = try self.createProgram(desc.vertex_shader, desc.fragment_shader);

    const pipeline = try self.allocator.create(struct {
        program: c.GLuint,
    });
    pipeline.* = .{ .program = program };

    const result = try self.allocator.create(renderer.Pipeline);
    result.* = .{
        .handle = pipeline,
        .vtable = &pipeline_vtable,
    };

    return result;
}

fn beginRenderPassImpl(ptr: *anyopaque, desc: renderer.RenderPassDescriptor) anyerror!*renderer.RenderPass {
    _ = ptr;
    _ = desc;
    return error.NotImplemented;
}

fn presentImpl(ptr: *anyopaque) anyerror!void {
    const self = @as(*GLESRenderer, @ptrCast(@alignCast(ptr)));

    c.glClearColor(0.0, 0.2, 0.4, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    _ = c.eglSwapBuffers(self.display, self.surface);
}

fn waitIdleImpl(ptr: *anyopaque) void {
    _ = ptr;
    c.glFinish();
}

fn bufferDeinitImpl(ptr: *anyopaque) void {
    const buffer = @as(*GLESBuffer, @ptrCast(@alignCast(ptr)));
    c.glDeleteBuffers(1, &buffer.id);
}

fn bufferMapImpl(ptr: *anyopaque) anyerror![]u8 {
    const buffer = @as(*GLESBuffer, @ptrCast(@alignCast(ptr)));
    c.glBindBuffer(buffer.target, buffer.id);
    const data = c.glMapBufferRange(buffer.target, 0, @intCast(buffer.size), c.GL_MAP_WRITE_BIT | c.GL_MAP_READ_BIT);
    if (data == null) {
        return error.BufferMapFailed;
    }
    return @as([*]u8, @ptrCast(data))[0..buffer.size];
}

fn bufferUnmapImpl(ptr: *anyopaque) void {
    const buffer = @as(*GLESBuffer, @ptrCast(@alignCast(ptr)));
    c.glBindBuffer(buffer.target, buffer.id);
    _ = c.glUnmapBuffer(buffer.target);
}

fn bufferWriteImpl(ptr: *anyopaque, data: []const u8, offset: usize) void {
    const buffer = @as(*GLESBuffer, @ptrCast(@alignCast(ptr)));
    c.glBindBuffer(buffer.target, buffer.id);
    c.glBufferSubData(buffer.target, @intCast(offset), @intCast(data.len), data.ptr);
}

fn pipelineDeinitImpl(ptr: *anyopaque) void {
    const pipeline = @as(*struct { program: c.GLuint }, @ptrCast(@alignCast(ptr)));
    c.glDeleteProgram(pipeline.program);
}

const buffer_vtable = renderer.Buffer.VTable{
    .deinit = bufferDeinitImpl,
    .map = bufferMapImpl,
    .unmap = bufferUnmapImpl,
    .write = bufferWriteImpl,
};

const pipeline_vtable = renderer.Pipeline.VTable{
    .deinit = pipelineDeinitImpl,
};

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
    const impl = try allocator.create(GLESRenderer);
    impl.* = try GLESRenderer.init(allocator);

    const r = try allocator.create(renderer.Renderer);
    r.* = .{
        .backend = .opengl_es,
        .impl = impl,
        .vtable = &vtable,
    };

    return r;
}