# Kline Documentation

Welcome to the comprehensive documentation for **Kline**, the cross-platform rendering engine built in Zig.

## 📖 Documentation Structure

- **[Getting Started](./getting_started.md)** - Quick setup and first steps
- **[Architecture Overview](./architecture.md)** - Engine design and structure
- **[API Reference](./api_reference.md)** - Complete API documentation
- **[Backend Guide](./backends.md)** - Platform-specific backend information
- **[Build System](./build_system.md)** - Compilation options and configuration
- **[Examples](./examples.md)** - Code examples and tutorials
- **[Performance Guide](./performance.md)** - Optimization and best practices
- **[Contributing](./contributing.md)** - Development guidelines

## 🎯 Current Status

**P1-P2 Complete** ✅ | **Next Phase**: P3 Advanced Rendering

### ✅ Implemented Features
- **Multi-Backend Rendering**: Vulkan, DirectX 12/13, Software renderer
- **Text Rendering System**: Font loading, glyph caching, layout engine
- **Advanced Shader System**: Multi-language compilation with caching
- **Multi-threading Architecture**: Parallel rendering and job system
- **Memory Management**: GPU memory pools and advanced allocators
- **Vector Graphics**: 2D rendering with paths and gradients
- **Compute Shaders**: GPU-accelerated parallel processing

### 🚀 Coming Next (P3)
- **PBR Materials**: Physically Based Rendering with Cook-Torrance BRDF
- **Advanced Lighting**: Point, directional, spot lights with IBL
- **Shadow Mapping**: Cascaded shadows, cube map shadows, soft shadows
- **Post-Processing**: HDR, tone mapping, SSAO, bloom, anti-aliasing

## 🏃‍♂️ Quick Start

```bash
# Clone and build
git clone <repo>
cd kline
zig build

# Run comprehensive demo
zig build demo

# Run simple example
zig build triangle
```

## 📋 Build Options

```bash
# Minimal build (software renderer only)
zig build -Dsoftware=true -Dvulkan=false -Ddx12=false

# Performance build (Vulkan + DirectX 12)
zig build -Dvulkan=true -Ddx12=true

# Full feature build (default)
zig build
```

## 📊 Platform Support

| Platform | Vulkan | DirectX 12 | DirectX 13 | Metal | OpenGL ES | Software |
|----------|--------|-------------|-------------|--------|-----------|----------|
| Windows  | ✅     | ✅          | ✅          | ❌     | ✅        | ✅       |
| Linux    | ✅     | ❌          | ❌          | ❌     | ✅        | ✅       |
| macOS    | ❌     | ❌          | ❌          | 🚧     | ✅        | ✅       |

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/kline/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/kline/discussions)
- **Documentation**: This documentation site
- **Examples**: [examples/ directory](../examples/)

---

*Kline v1.0 - Built with ❤️ in Zig*