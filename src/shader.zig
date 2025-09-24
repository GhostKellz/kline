const std = @import("std");
const renderer = @import("renderer.zig");
const builtin = @import("builtin");

pub const ShaderError = error{
    CompilationFailed,
    InvalidShaderType,
    UnsupportedTarget,
    FileNotFound,
    OutOfMemory,
    InvalidShaderSource,
};

pub const ShaderType = enum {
    vertex,
    fragment,
    compute,
    geometry,
    tessellation_control,
    tessellation_evaluation,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    compute,
    geometry,
    tess_control,
    tess_evaluation,

    pub fn toShaderType(self: ShaderStage) ShaderType {
        return switch (self) {
            .vertex => .vertex,
            .fragment => .fragment,
            .compute => .compute,
            .geometry => .geometry,
            .tess_control => .tessellation_control,
            .tess_evaluation => .tessellation_evaluation,
        };
    }
};

pub const ShaderLanguage = enum {
    hlsl,
    glsl,
    spirv,
    msl, // Metal Shading Language
    wgsl, // WebGPU Shading Language
};

pub const TargetBackend = enum {
    vulkan,
    directx12,
    directx13,
    metal,
    opengl_es,
    webgpu,
};

pub const ShaderCompileOptions = struct {
    source_language: ShaderLanguage = .hlsl,
    target_backend: TargetBackend,
    optimization_level: u8 = 2, // 0-3
    debug_info: bool = false,
    entry_point: []const u8 = "main",
    defines: ?std.StringHashMap([]const u8) = null,
    include_paths: ?[][]const u8 = null,
};

pub const CompiledShader = struct {
    allocator: std.mem.Allocator,
    bytecode: []u8,
    entry_point: []const u8,
    stage: ShaderStage,
    reflection_data: ?ShaderReflection = null,

    pub fn deinit(self: *CompiledShader) void {
        self.allocator.free(self.bytecode);
        if (self.reflection_data) |*reflection| {
            reflection.deinit();
        }
    }
};

pub const ShaderReflection = struct {
    allocator: std.mem.Allocator,
    inputs: std.ArrayList(ShaderInput),
    outputs: std.ArrayList(ShaderOutput),
    uniforms: std.ArrayList(ShaderUniform),
    textures: std.ArrayList(ShaderTexture),

    const ShaderInput = struct {
        name: []const u8,
        location: u32,
        type: ShaderDataType,
        size: u32,
    };

    const ShaderOutput = struct {
        name: []const u8,
        location: u32,
        type: ShaderDataType,
        size: u32,
    };

    const ShaderUniform = struct {
        name: []const u8,
        binding: u32,
        set: u32,
        type: ShaderDataType,
        size: u32,
        offset: u32,
    };

    const ShaderTexture = struct {
        name: []const u8,
        binding: u32,
        set: u32,
        dimension: TextureDimension,
    };

    const TextureDimension = enum {
        tex_1d,
        tex_2d,
        tex_3d,
        tex_cube,
        tex_2d_array,
        tex_cube_array,
    };

    pub fn init(allocator: std.mem.Allocator) ShaderReflection {
        return ShaderReflection{
            .allocator = allocator,
            .inputs = std.ArrayList(ShaderInput).init(allocator),
            .outputs = std.ArrayList(ShaderOutput).init(allocator),
            .uniforms = std.ArrayList(ShaderUniform).init(allocator),
            .textures = std.ArrayList(ShaderTexture).init(allocator),
        };
    }

    pub fn deinit(self: *ShaderReflection) void {
        self.inputs.deinit();
        self.outputs.deinit();
        self.uniforms.deinit();
        self.textures.deinit();
    }
};

pub const ShaderDataType = enum {
    float32,
    float32x2,
    float32x3,
    float32x4,
    int32,
    int32x2,
    int32x3,
    int32x4,
    uint32,
    uint32x2,
    uint32x3,
    uint32x4,
    bool,
    mat3x3,
    mat4x4,
    struct_type,
};

pub const ShaderCompiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ShaderCompiler {
        return ShaderCompiler{
            .allocator = allocator,
        };
    }

    pub fn compileFromSource(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        return switch (options.target_backend) {
            .vulkan => self.compileToSpirV(source, stage, options),
            .directx12, .directx13 => self.compileToDXBC(source, stage, options),
            .metal => self.compileToMSL(source, stage, options),
            .opengl_es => self.compileToGLSL(source, stage, options),
            .webgpu => self.compileToWGSL(source, stage, options),
        };
    }

    pub fn compileFromFile(
        self: *ShaderCompiler,
        file_path: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        const file = std.fs.cwd().openFile(file_path, .{}) catch return ShaderError.FileNotFound;
        defer file.close();

        const file_size = file.getEndPos() catch return ShaderError.FileNotFound;
        const source = self.allocator.alloc(u8, file_size) catch return ShaderError.OutOfMemory;
        defer self.allocator.free(source);

        _ = file.readAll(source) catch return ShaderError.FileNotFound;

        return self.compileFromSource(source, stage, options);
    }

    fn compileToSpirV(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        // For now, return a dummy SPIR-V bytecode
        // TODO: Integrate with glslc, shaderc, or DXC for actual compilation
        _ = source;
        _ = options;

        // Dummy SPIR-V header
        const dummy_spirv = [_]u8{
            0x03, 0x02, 0x23, 0x07, // Magic number
            0x00, 0x00, 0x01, 0x00, // Version
            0x00, 0x00, 0x00, 0x00, // Generator magic number
            0x00, 0x00, 0x00, 0x00, // Bound
            0x00, 0x00, 0x00, 0x00, // Schema (reserved, must be 0)
        };

        const bytecode = try self.allocator.dupe(u8, &dummy_spirv);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = bytecode,
            .entry_point = try self.allocator.dupe(u8, options.entry_point),
            .stage = stage,
            .reflection_data = null, // TODO: Generate reflection data
        };
    }

    fn compileToDXBC(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        // TODO: Integrate with DXC (DirectX Shader Compiler)
        _ = source;

        const target = switch (stage) {
            .vertex => "vs_5_0",
            .fragment => "ps_5_0",
            .compute => "cs_5_0",
            .geometry => "gs_5_0",
            .tess_control => "hs_5_0",
            .tess_evaluation => "ds_5_0",
        };
        _ = target;

        // Dummy DXBC bytecode
        const dummy_dxbc = [_]u8{ 0x44, 0x58, 0x42, 0x43 }; // DXBC signature

        const bytecode = try self.allocator.dupe(u8, &dummy_dxbc);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = bytecode,
            .entry_point = try self.allocator.dupe(u8, options.entry_point),
            .stage = stage,
            .reflection_data = null,
        };
    }

    fn compileToMSL(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        // TODO: Transpile to Metal Shading Language
        _ = stage;

        const msl_source = try self.allocator.dupe(u8, source);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = msl_source,
            .entry_point = try self.allocator.dupe(u8, options.entry_point),
            .stage = stage,
            .reflection_data = null,
        };
    }

    fn compileToGLSL(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        // TODO: Transpile to GLSL ES
        _ = stage;

        const glsl_source = try self.allocator.dupe(u8, source);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = glsl_source,
            .entry_point = try self.allocator.dupe(u8, options.entry_point),
            .stage = stage,
            .reflection_data = null,
        };
    }

    fn compileToWGSL(
        self: *ShaderCompiler,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) ShaderError!CompiledShader {
        // TODO: Transpile to WGSL
        _ = stage;

        const wgsl_source = try self.allocator.dupe(u8, source);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = wgsl_source,
            .entry_point = try self.allocator.dupe(u8, options.entry_point),
            .stage = stage,
            .reflection_data = null,
        };
    }
};

pub const ShaderCache = struct {
    allocator: std.mem.Allocator,
    cache: std.HashMap(u64, CompiledShader, std.hash_map.DefaultHashContext(u64), std.hash_map.default_max_load_percentage),
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !ShaderCache {
        // Ensure cache directory exists
        std.fs.cwd().makeDir(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return ShaderCache{
            .allocator = allocator,
            .cache = std.HashMap(u64, CompiledShader, std.hash_map.DefaultHashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .cache_dir = try allocator.dupe(u8, cache_dir),
        };
    }

    pub fn deinit(self: *ShaderCache) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.cache.deinit();
        self.allocator.free(self.cache_dir);
    }

    pub fn get(self: *ShaderCache, key: []const u8, stage: ShaderStage, options: ShaderCompileOptions) ?*const CompiledShader {
        const hash_key = self.computeHash(key, stage, options);
        return self.cache.getPtr(hash_key);
    }

    pub fn put(self: *ShaderCache, key: []const u8, stage: ShaderStage, options: ShaderCompileOptions, shader: CompiledShader) !void {
        const hash_key = self.computeHash(key, stage, options);
        try self.cache.put(hash_key, shader);

        // Write to disk for persistence
        try self.writeToDisk(hash_key, &shader);
    }

    fn computeHash(self: *ShaderCache, key: []const u8, stage: ShaderStage, options: ShaderCompileOptions) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(key);
        hasher.update(std.mem.asBytes(&stage));
        hasher.update(std.mem.asBytes(&options.target_backend));
        hasher.update(std.mem.asBytes(&options.optimization_level));
        hasher.update(options.entry_point);
        return hasher.final();
    }

    fn writeToDisk(self: *ShaderCache, hash_key: u64, shader: *const CompiledShader) !void {
        const file_name = try std.fmt.allocPrint(self.allocator, "{}/{}.cache", .{ self.cache_dir, hash_key });
        defer self.allocator.free(file_name);

        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();

        try file.writeAll(shader.bytecode);
    }

    fn readFromDisk(self: *ShaderCache, hash_key: u64) !?CompiledShader {
        const file_name = try std.fmt.allocPrint(self.allocator, "{}/{}.cache", .{ self.cache_dir, hash_key });
        defer self.allocator.free(file_name);

        const file = std.fs.cwd().openFile(file_name, .{}) catch return null;
        defer file.close();

        const file_size = try file.getEndPos();
        const bytecode = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(bytecode);

        return CompiledShader{
            .allocator = self.allocator,
            .bytecode = bytecode,
            .entry_point = try self.allocator.dupe(u8, "main"),
            .stage = .vertex, // TODO: Store stage info in cache file
            .reflection_data = null,
        };
    }
};

pub const ShaderManager = struct {
    allocator: std.mem.Allocator,
    compiler: ShaderCompiler,
    cache: ShaderCache,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !ShaderManager {
        return ShaderManager{
            .allocator = allocator,
            .compiler = ShaderCompiler.init(allocator),
            .cache = try ShaderCache.init(allocator, cache_dir),
        };
    }

    pub fn deinit(self: *ShaderManager) void {
        self.cache.deinit();
    }

    pub fn loadShader(
        self: *ShaderManager,
        source: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) !CompiledShader {
        // Check cache first
        if (self.cache.get(source, stage, options)) |cached_shader| {
            // Return a copy
            const bytecode = try self.allocator.dupe(u8, cached_shader.bytecode);
            const entry_point = try self.allocator.dupe(u8, cached_shader.entry_point);

            return CompiledShader{
                .allocator = self.allocator,
                .bytecode = bytecode,
                .entry_point = entry_point,
                .stage = cached_shader.stage,
                .reflection_data = null,
            };
        }

        // Compile and cache
        const shader = try self.compiler.compileFromSource(source, stage, options);
        try self.cache.put(source, stage, options, shader);

        return shader;
    }

    pub fn loadShaderFromFile(
        self: *ShaderManager,
        file_path: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) !CompiledShader {
        return try self.compiler.compileFromFile(file_path, stage, options);
    }

    pub fn hotReloadShader(
        self: *ShaderManager,
        file_path: []const u8,
        stage: ShaderStage,
        options: ShaderCompileOptions,
    ) !CompiledShader {
        // Force recompilation for hot reload
        return try self.compiler.compileFromFile(file_path, stage, options);
    }
};

// High-level API
pub fn createShaderManager(allocator: std.mem.Allocator) !ShaderManager {
    return ShaderManager.init(allocator, ".shader_cache");
}

// Common shader source templates
pub const VertexShaderTemplate = struct {
    pub const basic_3d =
        \\cbuffer VertexBuffer : register(b0)
        \\{
        \\    matrix mvp;
        \\};
        \\
        \\struct VS_INPUT
        \\{
        \\    float3 pos : POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\struct PS_INPUT
        \\{
        \\    float4 pos : SV_POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\PS_INPUT main(VS_INPUT input)
        \\{
        \\    PS_INPUT output;
        \\    output.pos = mul(float4(input.pos, 1.0f), mvp);
        \\    output.color = input.color;
        \\    output.uv = input.uv;
        \\    return output;
        \\}
    ;

    pub const basic_2d =
        \\struct VS_INPUT
        \\{
        \\    float2 pos : POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\struct PS_INPUT
        \\{
        \\    float4 pos : SV_POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\PS_INPUT main(VS_INPUT input)
        \\{
        \\    PS_INPUT output;
        \\    output.pos = float4(input.pos, 0.0f, 1.0f);
        \\    output.color = input.color;
        \\    output.uv = input.uv;
        \\    return output;
        \\}
    ;
};

pub const FragmentShaderTemplate = struct {
    pub const basic_color =
        \\struct PS_INPUT
        \\{
        \\    float4 pos : SV_POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\float4 main(PS_INPUT input) : SV_Target
        \\{
        \\    return input.color;
        \\}
    ;

    pub const textured =
        \\Texture2D shaderTexture;
        \\SamplerState SampleType;
        \\
        \\struct PS_INPUT
        \\{
        \\    float4 pos : SV_POSITION;
        \\    float4 color : COLOR;
        \\    float2 uv : TEXCOORD;
        \\};
        \\
        \\float4 main(PS_INPUT input) : SV_Target
        \\{
        \\    float4 textureColor = shaderTexture.Sample(SampleType, input.uv);
        \\    return textureColor * input.color;
        \\}
    ;
};

// Test function
test "shader system basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = ShaderCompiler.init(allocator);

    const options = ShaderCompileOptions{
        .target_backend = .vulkan,
        .optimization_level = 2,
    };

    var shader = try compiler.compileFromSource(
        VertexShaderTemplate.basic_2d,
        .vertex,
        options,
    );
    defer shader.deinit();

    try std.testing.expect(shader.bytecode.len > 0);
    try std.testing.expect(shader.stage == .vertex);
}