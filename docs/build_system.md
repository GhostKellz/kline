# Kline Build System

This document covers Kline's advanced build system, featuring optional backend compilation, conditional features, and optimization settings.

## 🎛️ Build Options Overview

Kline uses Zig's build system to provide fine-grained control over compilation targets, features, and optimizations. This allows you to build only what you need, reducing binary size and compilation time.

## 🏗️ Basic Build Commands

### Standard Builds
```bash
# Default build (all features enabled)
zig build

# Release build optimized for speed
zig build -Doptimize=ReleaseFast

# Release build optimized for size
zig build -Doptimize=ReleaseSmall

# Debug build with safety checks
zig build -Doptimize=Debug

# Safe release build
zig build -Doptimize=ReleaseSafe
```

### Running Examples
```bash
# Run comprehensive P1-P2 demo
zig build demo

# Run triangle example
zig build triangle

# Run tests
zig build test
```

### Help and Information
```bash
# Show all available build options
zig build --help

# List all build steps
zig build --list-steps
```

## 🎯 Backend Selection

Control which graphics backends are included in your build:

### Individual Backend Flags
```bash
# Vulkan backend (default: true)
-Dvulkan=[bool]

# DirectX 12 backend (default: true)
-Ddx12=[bool]

# DirectX 13 backend (default: true)
-Ddx13=[bool]

# Metal backend (default: true)
-Dmetal=[bool]

# OpenGL ES backend (default: true)
-Dopengl=[bool]

# Software renderer (default: true)
-Dsoftware=[bool]
```

### Backend-Specific Builds

#### Minimal Software-Only Build
```bash
# Smallest possible build - software renderer only
zig build -Dvulkan=false -Ddx12=false -Ddx13=false -Dmetal=false -Dopengl=false
```
**Use case**: Embedded systems, CI/CD environments, testing

#### High-Performance Builds
```bash
# Vulkan-only build (Linux/Windows performance)
zig build -Ddx12=false -Ddx13=false -Dmetal=false -Dopengl=false -Dsoftware=false

# DirectX 12-only build (Windows performance)
zig build -Dvulkan=false -Ddx13=false -Dmetal=false -Dopengl=false -Dsoftware=false

# Dual high-performance (Vulkan + DirectX 12)
zig build -Ddx13=false -Dmetal=false -Dopengl=false -Dsoftware=false
```

#### Platform-Specific Builds
```bash
# Windows build
zig build -Dvulkan=true -Ddx12=true -Ddx13=true -Dmetal=false -Dopengl=true

# Linux build
zig build -Dvulkan=true -Ddx12=false -Ddx13=false -Dmetal=false -Dopengl=true

# macOS build (when Metal is complete)
zig build -Dvulkan=false -Ddx12=false -Ddx13=false -Dmetal=true -Dopengl=true
```

## 🎨 Feature Control

Enable or disable major features to customize your build:

### Feature Flags
```bash
# Text rendering system (default: true)
-Dtext=[bool]

# Compute shader support (default: true)
-Dcompute=[bool]

# Advanced memory management (default: true)
-Dadvanced-memory=[bool]
```

### Feature-Specific Builds

#### Minimal Graphics Build
```bash
# Basic rendering only - no text, no compute
zig build -Dtext=false -Dcompute=false -Dadvanced-memory=false
```
**Use case**: Simple graphics applications, embedded systems

#### Text-Heavy Applications
```bash
# Optimize for text rendering applications
zig build -Dtext=true -Dcompute=false -Dsoftware=true -Dvulkan=false -Ddx12=false
```
**Use case**: Text editors, documentation tools, UI frameworks

#### Compute-Focused Build
```bash
# Optimize for GPU compute workloads
zig build -Dcompute=true -Dtext=false -Dvulkan=true -Dsoftware=false
```
**Use case**: Scientific computing, image processing, ML inference

## 🚀 P3 Advanced Features (Coming Soon)

Future build options for P3 advanced rendering features:

### P3 Feature Flags
```bash
# PBR material system
-Dpbr=[bool]              # Enable physically-based rendering

# Shadow mapping
-Dshadows=[bool]          # Enable shadow mapping system

# Post-processing pipeline
-Dpost_processing=[bool]  # Enable post-processing effects

# Image-based lighting
-Dibl=[bool]              # Enable IBL support

# HDR rendering
-Dhdr=[bool]              # Enable high dynamic range

# Screen-space ambient occlusion
-Dssao=[bool]             # Enable SSAO effects
```

### P3 Performance Options
```bash
# Shadow quality levels
-Dshadow_quality=[enum]   # Options: low, medium, high, ultra

# Maximum dynamic lights
-Dmax_lights=[int]        # Default: 256, Range: 1-1024

# Shadow map resolution
-Dshadow_resolution=[int] # Default: 2048, Options: 512, 1024, 2048, 4096
```

### P3 Build Examples
```bash
# Full P3 features (future)
zig build -Dpbr=true -Dshadows=true -Dpost_processing=true -Dibl=true

# Mobile-optimized P3 (future)
zig build -Dpbr=true -Dshadows=true -Dshadow_quality=low -Dmax_lights=16

# Desktop performance P3 (future)
zig build -Dpbr=true -Dshadows=true -Dshadow_quality=ultra -Dmax_lights=512
```

## 🎯 Target Configuration

### Cross-Compilation
```bash
# Target Windows from Linux
zig build -Dtarget=x86_64-windows

# Target Linux from macOS
zig build -Dtarget=x86_64-linux

# Target ARM64 (M1 Mac, ARM Linux)
zig build -Dtarget=aarch64-macos
zig build -Dtarget=aarch64-linux
```

### CPU-Specific Optimization
```bash
# Optimize for specific CPU
zig build -Dcpu=native      # Optimize for build machine
zig build -Dcpu=x86_64_v3   # Modern x86_64 with AVX2
zig build -Dcpu=baseline    # Maximum compatibility
```

## 📊 Build Performance

### Parallel Compilation
```bash
# Use all CPU cores (default)
zig build

# Limit concurrent jobs
zig build -j4

# Single-threaded build
zig build -j1
```

### Incremental Builds
```bash
# Enable incremental compilation (faster rebuilds)
zig build -fincremental

# Force full rebuild
zig build -fno-incremental
```

### Build Caching
```bash
# Custom cache directory
zig build --cache-dir /tmp/kline-cache

# Global cache directory
zig build --global-cache-dir ~/.cache/kline
```

## 🔍 Build Analysis

### Verbose Output
```bash
# Show compilation commands
zig build --verbose

# Show detailed build summary
zig build --summary all

# Show only failures
zig build --summary failures
```

### Time and Memory Analysis
```bash
# Memory usage limit
zig build --maxrss 2GB

# Skip memory-intensive steps if needed
zig build --skip-oom-steps

# Build time analysis
zig build --time-report
```

## 🎛️ Advanced Configuration

### Custom Build File
```bash
# Use custom build.zig
zig build --build-file custom_build.zig
```

### Environment Variables
```bash
# Set Zig library path
ZIG_LIB_DIR=/path/to/zig/lib zig build

# Custom global cache
ZIG_GLOBAL_CACHE_DIR=~/.cache/zig zig build
```

## 📋 Build Presets

Here are some common build configurations for different use cases:

### Development Build
```bash
# Fast compilation, debug info, all features
zig build -Doptimize=Debug --verbose
```

### Production Release
```bash
# Maximum performance, minimal size, essential features only
zig build -Doptimize=ReleaseFast -Dvulkan=true -Ddx12=true -Dsoftware=false
```

### CI/CD Build
```bash
# Software renderer only for headless testing
zig build -Dsoftware=true -Dvulkan=false -Ddx12=false -Dmetal=false -Dopengl=false
```

### Mobile/Embedded
```bash
# Minimal features, size-optimized
zig build -Doptimize=ReleaseSmall -Dopengl=true -Dsoftware=true -Dtext=false -Dcompute=false
```

### Research/Compute
```bash
# Compute-focused with Vulkan
zig build -Dvulkan=true -Dcompute=true -Dtext=false -Dsoftware=false
```

## 🐛 Troubleshooting

### Common Build Issues

#### Missing Dependencies
```bash
# Error: Vulkan headers not found
sudo apt install vulkan-sdk libvulkan-dev  # Linux
# Or disable Vulkan: zig build -Dvulkan=false
```

#### Platform Incompatibility
```bash
# Error: DirectX not available on Linux
zig build -Ddx12=false -Ddx13=false  # Disable DirectX on non-Windows
```

#### Memory Issues
```bash
# Error: Out of memory during compilation
zig build --maxrss 1GB -j2  # Reduce memory usage and parallelism
```

### Build Verification

#### Test Your Build
```bash
# Run tests to verify functionality
zig build test

# Run demo to verify features
zig build demo

# Check specific backend
zig build triangle  # Uses configured backends
```

#### Binary Analysis
```bash
# Check binary size
ls -lh zig-out/bin/

# Analyze symbols (Linux/macOS)
nm zig-out/bin/kline | grep -i vulkan

# Check dependencies (Linux)
ldd zig-out/bin/kline
```

## 📈 Build Size Comparison

Approximate binary sizes for different configurations:

| Configuration | Size (Debug) | Size (Release) | Features |
|---------------|--------------|----------------|----------|
| Full build | ~50MB | ~15MB | All backends + features |
| Vulkan only | ~25MB | ~8MB | High-performance graphics |
| Software only | ~10MB | ~3MB | CPU rendering, maximum compatibility |
| Minimal | ~5MB | ~1.5MB | Software renderer, no text/compute |

## 🔮 Future Build Features

Planned enhancements for the build system:

- **Profile-guided optimization**: Use runtime data to optimize builds
- **Link-time optimization**: Cross-module optimization for maximum performance
- **Static analysis**: Built-in code quality and security checks
- **Package management**: Automatic dependency resolution
- **Cloud builds**: Distributed compilation support

## 📝 Custom Build Scripts

You can extend the build system by creating custom build configurations:

### Custom Backend Selection
```zig
// custom_build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Your custom build logic
    const enable_experimental = b.option(bool, "experimental", "Enable experimental features") orelse false;

    if (enable_experimental) {
        // Enable bleeding-edge features
    }
}
```

### Integration with Other Projects
```zig
// In your project's build.zig
const kline = b.dependency("kline", .{
    .target = target,
    .optimize = optimize,
    .vulkan = true,
    .dx12 = false,  // Disable DirectX for cross-platform project
    .text = true,
    .compute = false,
});

exe.root_module.addImport("kline", kline.module("kline"));
```

This build system provides the flexibility to create optimized builds for any use case, from embedded systems to high-performance gaming applications.