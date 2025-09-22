const std = @import("std");

pub const PoolError = error{
    OutOfMemory,
    InvalidAlignment,
    BlockTooLarge,
};

pub const MemoryPool = struct {
    allocator: std.mem.Allocator,
    block_size: usize,
    block_count: usize,
    alignment: usize,
    memory: []u8,
    free_list: ?*Block,
    used_blocks: usize,
    peak_usage: usize,

    const Block = struct {
        next: ?*Block,
        size: usize,
        in_use: bool,
    };

    pub fn init(allocator: std.mem.Allocator, block_size: usize, block_count: usize, comptime alignment: usize) !MemoryPool {
        if (!std.mem.isValidAlign(alignment)) {
            return PoolError.InvalidAlignment;
        }

        const aligned_block_size = std.mem.alignForward(usize, block_size + @sizeOf(Block), alignment);
        const total_size = aligned_block_size * block_count;

        const memory = try allocator.alignedAlloc(u8, @as(std.mem.Alignment, @enumFromInt(alignment)), total_size);
        errdefer allocator.free(memory);

        var pool = MemoryPool{
            .allocator = allocator,
            .block_size = block_size,
            .block_count = block_count,
            .alignment = alignment,
            .memory = memory,
            .free_list = null,
            .used_blocks = 0,
            .peak_usage = 0,
        };

        pool.initFreeList();
        return pool;
    }

    fn initFreeList(self: *MemoryPool) void {
        const aligned_block_size = std.mem.alignForward(usize, self.block_size + @sizeOf(Block), self.alignment);

        var i: usize = 0;
        while (i < self.block_count) : (i += 1) {
            const offset = i * aligned_block_size;
            const block = @as(*Block, @ptrCast(@alignCast(&self.memory[offset])));
            block.size = self.block_size;
            block.in_use = false;
            block.next = self.free_list;
            self.free_list = block;
        }
    }

    pub fn deinit(self: *MemoryPool) void {
        self.allocator.free(self.memory);
    }

    pub fn alloc(self: *MemoryPool, size: usize) ![]u8 {
        if (size > self.block_size) {
            return PoolError.BlockTooLarge;
        }

        if (self.free_list) |block| {
            self.free_list = block.next;
            block.in_use = true;
            block.next = null;

            self.used_blocks += 1;
            if (self.used_blocks > self.peak_usage) {
                self.peak_usage = self.used_blocks;
            }

            const data_ptr = @as([*]u8, @ptrCast(block)) + @sizeOf(Block);
            return data_ptr[0..size];
        }

        return PoolError.OutOfMemory;
    }

    pub fn free(self: *MemoryPool, ptr: []u8) void {
        const block_ptr = @as([*]u8, @ptrCast(ptr.ptr)) - @sizeOf(Block);
        const block = @as(*Block, @ptrCast(@alignCast(block_ptr)));

        if (!block.in_use) {
            return;
        }

        block.in_use = false;
        block.next = self.free_list;
        self.free_list = block;
        self.used_blocks -= 1;
    }

    pub fn reset(self: *MemoryPool) void {
        self.free_list = null;
        self.used_blocks = 0;
        self.initFreeList();
    }

    pub fn getUsage(self: *const MemoryPool) f32 {
        return @as(f32, @floatFromInt(self.used_blocks)) / @as(f32, @floatFromInt(self.block_count));
    }

    pub fn getPeakUsage(self: *const MemoryPool) f32 {
        return @as(f32, @floatFromInt(self.peak_usage)) / @as(f32, @floatFromInt(self.block_count));
    }
};

pub const RingBuffer = struct {
    allocator: std.mem.Allocator,
    memory: []u8,
    head: usize,
    tail: usize,
    size: usize,
    alignment: usize,

    pub fn init(allocator: std.mem.Allocator, size: usize, comptime alignment: usize) !RingBuffer {
        if (!std.mem.isValidAlign(alignment)) {
            return PoolError.InvalidAlignment;
        }

        const memory = try allocator.alignedAlloc(u8, @as(std.mem.Alignment, @enumFromInt(alignment)), size);

        return .{
            .allocator = allocator,
            .memory = memory,
            .head = 0,
            .tail = 0,
            .size = size,
            .alignment = alignment,
        };
    }

    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.memory);
    }

    pub fn alloc(self: *RingBuffer, req_size: usize) ![]u8 {
        const aligned_size = std.mem.alignForward(usize, req_size, self.alignment);

        if (aligned_size > self.size) {
            return PoolError.BlockTooLarge;
        }

        if (self.head >= self.tail) {
            const available = self.size - self.head;
            if (available >= aligned_size) {
                const ptr = self.memory[self.head..self.head + req_size];
                self.head = (self.head + aligned_size) % self.size;
                return ptr;
            }

            if (self.tail >= aligned_size) {
                self.head = 0;
                const ptr = self.memory[0..req_size];
                self.head = aligned_size;
                return ptr;
            }
        } else {
            const available = self.tail - self.head;
            if (available >= aligned_size) {
                const ptr = self.memory[self.head..self.head + req_size];
                self.head += aligned_size;
                return ptr;
            }
        }

        return PoolError.OutOfMemory;
    }

    pub fn free(self: *RingBuffer, size: usize) void {
        const aligned_size = std.mem.alignForward(usize, size, self.alignment);
        self.tail = (self.tail + aligned_size) % self.size;
    }

    pub fn reset(self: *RingBuffer) void {
        self.head = 0;
        self.tail = 0;
    }

    pub fn getUsage(self: *const RingBuffer) f32 {
        const used = if (self.head >= self.tail)
            self.head - self.tail
        else
            self.size - self.tail + self.head;

        return @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(self.size));
    }
};

pub const BuddyAllocator = struct {
    allocator: std.mem.Allocator,
    memory: []u8,
    min_block_size: usize,
    max_order: u8,
    free_lists: []?*FreeBlock,
    block_status: []u8,

    const FreeBlock = struct {
        next: ?*FreeBlock,
        order: u8,
    };

    pub fn init(allocator: std.mem.Allocator, size: usize, min_block_size: usize) !BuddyAllocator {
        const max_order = @as(u8, @intCast(std.math.log2(size / min_block_size)));
        const memory = try allocator.alloc(u8, size);
        errdefer allocator.free(memory);

        const free_lists = try allocator.alloc(?*FreeBlock, max_order + 1);
        errdefer allocator.free(free_lists);
        @memset(free_lists, null);

        const block_count = size / min_block_size;
        const block_status = try allocator.alloc(u8, block_count);
        errdefer allocator.free(block_status);
        @memset(block_status, 0);

        var buddy = BuddyAllocator{
            .allocator = allocator,
            .memory = memory,
            .min_block_size = min_block_size,
            .max_order = max_order,
            .free_lists = free_lists,
            .block_status = block_status,
        };

        const root_block = @as(*FreeBlock, @ptrCast(@alignCast(memory.ptr)));
        root_block.next = null;
        root_block.order = max_order;
        buddy.free_lists[max_order] = root_block;

        return buddy;
    }

    pub fn deinit(self: *BuddyAllocator) void {
        self.allocator.free(self.block_status);
        self.allocator.free(self.free_lists);
        self.allocator.free(self.memory);
    }

    pub fn alloc(self: *BuddyAllocator, size: usize) ![]u8 {
        const order = self.getOrder(size);
        if (order > self.max_order) {
            return PoolError.BlockTooLarge;
        }

        const block = try self.allocBlock(order);
        return @as([*]u8, @ptrCast(block))[0..size];
    }

    fn getOrder(self: *BuddyAllocator, size: usize) u8 {
        var order: u8 = 0;
        var block_size = self.min_block_size;

        while (block_size < size) : (order += 1) {
            block_size *= 2;
        }

        return order;
    }

    fn allocBlock(self: *BuddyAllocator, order: u8) !*FreeBlock {
        if (self.free_lists[order]) |block| {
            self.free_lists[order] = block.next;
            return block;
        }

        if (order >= self.max_order) {
            return PoolError.OutOfMemory;
        }

        const parent = try self.allocBlock(order + 1);
        const block_size = self.min_block_size * (@as(usize, 1) << order);
        const buddy = @as(*FreeBlock, @ptrCast(@as([*]u8, @ptrCast(parent)) + block_size));

        buddy.next = self.free_lists[order];
        buddy.order = order;
        self.free_lists[order] = buddy;

        parent.order = order;
        return parent;
    }

    pub fn free(self: *BuddyAllocator, ptr: []u8) void {
        const block = @as(*FreeBlock, @ptrCast(@alignCast(ptr.ptr)));
        const order = self.getOrder(ptr.len);

        block.next = self.free_lists[order];
        block.order = order;
        self.free_lists[order] = block;

        self.coalesce(block, order);
    }

    fn coalesce(self: *BuddyAllocator, block: *FreeBlock, order: u8) void {
        if (order >= self.max_order) {
            return;
        }

        const block_size = self.min_block_size * (@as(usize, 1) << order);
        const block_addr = @intFromPtr(block);
        const base_addr = @intFromPtr(self.memory.ptr);
        const block_index = (block_addr - base_addr) / block_size;

        const buddy_index = block_index ^ 1;
        const buddy_addr = base_addr + buddy_index * block_size;
        const buddy = @as(*FreeBlock, @ptrFromInt(buddy_addr));

        var prev: ?*FreeBlock = null;
        var curr = self.free_lists[order];

        while (curr) |current| {
            if (current == buddy) {
                if (prev) |p| {
                    p.next = current.next;
                } else {
                    self.free_lists[order] = current.next;
                }

                if (prev) |p| {
                    if (p == block) {
                        if (prev == current) {
                            self.free_lists[order] = block.next;
                        } else {
                            prev = null;
                            curr = self.free_lists[order];
                            while (curr) |c| {
                                if (c.next == block) {
                                    c.next = block.next;
                                    break;
                                }
                                curr = c.next;
                            }
                        }
                    }
                } else {
                    self.free_lists[order] = block.next;
                }

                const merged = if (block_addr < buddy_addr) block else buddy;
                merged.order = order + 1;
                merged.next = self.free_lists[order + 1];
                self.free_lists[order + 1] = merged;

                self.coalesce(merged, order + 1);
                return;
            }

            prev = current;
            curr = current.next;
        }
    }
};

pub const GPUMemoryPool = struct {
    renderer: *@import("renderer.zig").Renderer,
    allocator: std.mem.Allocator,
    buffer_pools: std.AutoHashMap(usize, MemoryPool),
    texture_cache: std.ArrayList(TextureEntry),
    total_gpu_memory: usize,
    used_gpu_memory: usize,

    const TextureEntry = struct {
        texture: *@import("renderer.zig").Texture,
        last_used: i64,
        ref_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator, renderer: *@import("renderer.zig").Renderer) !GPUMemoryPool {
        return .{
            .renderer = renderer,
            .allocator = allocator,
            .buffer_pools = std.AutoHashMap(usize, MemoryPool).init(allocator),
            .texture_cache = std.ArrayList(TextureEntry).init(allocator),
            .total_gpu_memory = 2 * 1024 * 1024 * 1024,
            .used_gpu_memory = 0,
        };
    }

    pub fn deinit(self: *GPUMemoryPool) void {
        var it = self.buffer_pools.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.buffer_pools.deinit();

        for (self.texture_cache.items) |entry| {
            entry.texture.deinit();
        }
        self.texture_cache.deinit();
    }

    pub fn allocBuffer(self: *GPUMemoryPool, size: usize) !*@import("renderer.zig").Buffer {
        const aligned_size = std.mem.alignForward(usize, size, 256);

        const pool = self.buffer_pools.get(aligned_size) orelse blk: {
            const new_pool = try MemoryPool.init(self.allocator, aligned_size, 64, 256);
            try self.buffer_pools.put(aligned_size, new_pool);
            break :blk self.buffer_pools.getPtr(aligned_size).?;
        };

        const memory = try pool.alloc(size);
        _ = memory;

        const desc = @import("renderer.zig").BufferDescriptor{
            .size = size,
            .usage = .{
                .vertex = true,
                .uniform = true,
                .storage = true,
                .transfer_src = true,
                .transfer_dst = true,
            },
            .mapped_at_creation = false,
        };

        const buffer = try self.renderer.createBuffer(desc);
        self.used_gpu_memory += size;

        return buffer;
    }

    pub fn freeBuffer(self: *GPUMemoryPool, buffer: *@import("renderer.zig").Buffer) void {
        self.used_gpu_memory -= buffer.size;
        buffer.deinit();
    }

    pub fn getMemoryUsage(self: *const GPUMemoryPool) f32 {
        return @as(f32, @floatFromInt(self.used_gpu_memory)) / @as(f32, @floatFromInt(self.total_gpu_memory));
    }

    pub fn defragment(self: *GPUMemoryPool) void {
        _ = self;
    }
};