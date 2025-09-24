const std = @import("std");
const renderer = @import("renderer.zig");

pub const ThreadingError = error{
    ThreadCreationFailed,
    JobQueueFull,
    InvalidThreadCount,
    OutOfMemory,
    ThreadPoolShutdown,
};

pub const JobPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
};

pub const Job = struct {
    function: *const fn (*anyopaque) void,
    data: *anyopaque,
    priority: JobPriority = .normal,
    completion_event: ?*std.Thread.ResetEvent = null,
};

pub const WorkerThread = struct {
    allocator: std.mem.Allocator,
    thread: std.Thread,
    thread_pool: *ThreadPool,
    running: std.atomic.Value(bool),
    id: u32,

    fn workerMain(self: *WorkerThread) void {
        while (self.running.load(.acquire)) {
            if (self.thread_pool.getJob()) |job| {
                job.function(job.data);
                if (job.completion_event) |event| {
                    event.set();
                }
                self.thread_pool.recycleJob(job);
            } else {
                std.Thread.yield() catch {};
            }
        }
    }
};

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    workers: []WorkerThread,
    job_queue: JobQueue,
    shutdown: std.atomic.Value(bool),

    const JobQueue = struct {
        allocator: std.mem.Allocator,
        jobs: std.ArrayList(Job),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !JobQueue {
            var jobs = std.ArrayList(Job).init(allocator);
            try jobs.ensureTotalCapacity(capacity);

            return JobQueue{
                .allocator = allocator,
                .jobs = jobs,
                .mutex = std.Thread.Mutex{},
                .condition = std.Thread.Condition{},
            };
        }

        pub fn deinit(self: *JobQueue) void {
            self.jobs.deinit();
        }

        pub fn push(self: *JobQueue, job: Job) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.jobs.items.len >= self.jobs.capacity) {
                return ThreadingError.JobQueueFull;
            }

            // Insert job based on priority (simple priority queue)
            var insert_index = self.jobs.items.len;
            for (self.jobs.items, 0..) |existing_job, i| {
                if (@intFromEnum(job.priority) > @intFromEnum(existing_job.priority)) {
                    insert_index = i;
                    break;
                }
            }

            try self.jobs.insert(insert_index, job);
            self.condition.signal();
        }

        pub fn pop(self: *JobQueue) ?Job {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.jobs.items.len == 0) {
                return null;
            }

            return self.jobs.orderedRemove(0);
        }

        pub fn popWithWait(self: *JobQueue) ?Job {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.jobs.items.len == 0) {
                self.condition.wait(&self.mutex);
            }

            if (self.jobs.items.len > 0) {
                return self.jobs.orderedRemove(0);
            }

            return null;
        }
    };

    pub fn init(allocator: std.mem.Allocator, thread_count: u32, job_queue_capacity: usize) !ThreadPool {
        if (thread_count == 0) {
            return ThreadingError.InvalidThreadCount;
        }

        const workers = try allocator.alloc(WorkerThread, thread_count);
        var job_queue = try JobQueue.init(allocator, job_queue_capacity);

        var pool = ThreadPool{
            .allocator = allocator,
            .workers = workers,
            .job_queue = job_queue,
            .shutdown = std.atomic.Value(bool).init(false),
        };

        // Start worker threads
        for (workers, 0..) |*worker, i| {
            worker.* = WorkerThread{
                .allocator = allocator,
                .thread = undefined,
                .thread_pool = &pool,
                .running = std.atomic.Value(bool).init(true),
                .id = @intCast(i),
            };

            worker.thread = std.Thread.spawn(.{}, WorkerThread.workerMain, .{worker}) catch {
                // Cleanup on failure
                pool.shutdown.store(true, .release);
                return ThreadingError.ThreadCreationFailed;
            };
        }

        return pool;
    }

    pub fn deinit(self: *ThreadPool) void {
        self.shutdown.store(true, .release);

        // Signal all workers to wake up and check shutdown flag
        self.job_queue.mutex.lock();
        self.job_queue.condition.broadcast();
        self.job_queue.mutex.unlock();

        // Stop all workers
        for (self.workers) |*worker| {
            worker.running.store(false, .release);
        }

        // Wait for all threads to finish
        for (self.workers) |*worker| {
            worker.thread.join();
        }

        self.job_queue.deinit();
        self.allocator.free(self.workers);
    }

    pub fn submitJob(self: *ThreadPool, job: Job) !void {
        if (self.shutdown.load(.acquire)) {
            return ThreadingError.ThreadPoolShutdown;
        }

        try self.job_queue.push(job);
    }

    pub fn getJob(self: *ThreadPool) ?Job {
        return self.job_queue.pop();
    }

    pub fn recycleJob(self: *ThreadPool, job: Job) void {
        _ = self;
        _ = job;
        // Could implement job object pooling here
    }

    pub fn getWorkerCount(self: *ThreadPool) u32 {
        return @intCast(self.workers.len);
    }

    pub fn waitForAll(self: *ThreadPool) void {
        // Simple busy wait until job queue is empty
        // In production, you'd want a more sophisticated completion tracking system
        while (true) {
            self.job_queue.mutex.lock();
            const empty = self.job_queue.jobs.items.len == 0;
            self.job_queue.mutex.unlock();

            if (empty) break;

            std.Thread.yield() catch {};
        }
    }
};

pub const RenderCommandBuffer = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(RenderCommand),
    mutex: std.Thread.Mutex,

    const RenderCommand = union(enum) {
        draw: DrawCommand,
        set_pipeline: SetPipelineCommand,
        set_buffer: SetBufferCommand,
        clear: ClearCommand,
        barrier: BarrierCommand,
    };

    const DrawCommand = struct {
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    };

    const SetPipelineCommand = struct {
        pipeline: *renderer.Pipeline,
    };

    const SetBufferCommand = struct {
        slot: u32,
        buffer: *renderer.Buffer,
    };

    const ClearCommand = struct {
        color: [4]f32,
    };

    const BarrierCommand = struct {
        // Resource transition barriers for GPU synchronization
        // Implementation depends on graphics API
        resource_type: ResourceType,

        const ResourceType = enum {
            buffer,
            texture,
        };
    };

    pub fn init(allocator: std.mem.Allocator) RenderCommandBuffer {
        return RenderCommandBuffer{
            .allocator = allocator,
            .commands = std.ArrayList(RenderCommand).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *RenderCommandBuffer) void {
        self.commands.deinit();
    }

    pub fn clear(self: *RenderCommandBuffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.commands.clearRetainingCapacity();
    }

    pub fn draw(self: *RenderCommandBuffer, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(RenderCommand{
            .draw = DrawCommand{
                .vertex_count = vertex_count,
                .instance_count = instance_count,
                .first_vertex = first_vertex,
                .first_instance = first_instance,
            },
        });
    }

    pub fn setPipeline(self: *RenderCommandBuffer, pipeline: *renderer.Pipeline) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(RenderCommand{
            .set_pipeline = SetPipelineCommand{
                .pipeline = pipeline,
            },
        });
    }

    pub fn setBuffer(self: *RenderCommandBuffer, slot: u32, buffer: *renderer.Buffer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(RenderCommand{
            .set_buffer = SetBufferCommand{
                .slot = slot,
                .buffer = buffer,
            },
        });
    }

    pub fn execute(self: *RenderCommandBuffer, render_pass: *renderer.RenderPass) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.commands.items) |command| {
            switch (command) {
                .draw => |draw_cmd| {
                    render_pass.draw(draw_cmd.vertex_count, draw_cmd.instance_count, draw_cmd.first_vertex, draw_cmd.first_instance);
                },
                .set_pipeline => |pipeline_cmd| {
                    render_pass.setPipeline(pipeline_cmd.pipeline);
                },
                .set_buffer => |buffer_cmd| {
                    render_pass.setVertexBuffer(buffer_cmd.slot, buffer_cmd.buffer);
                },
                .clear => |clear_cmd| {
                    _ = clear_cmd; // TODO: Implement clear command execution
                },
                .barrier => |barrier_cmd| {
                    _ = barrier_cmd; // TODO: Implement barrier execution
                },
            }
        }
    }
};

pub const ParallelRenderSystem = struct {
    allocator: std.mem.Allocator,
    thread_pool: ThreadPool,
    command_buffers: []RenderCommandBuffer,
    main_command_buffer: RenderCommandBuffer,

    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !ParallelRenderSystem {
        const thread_pool = try ThreadPool.init(allocator, thread_count, 1000);
        const command_buffers = try allocator.alloc(RenderCommandBuffer, thread_count);

        for (command_buffers) |*buffer| {
            buffer.* = RenderCommandBuffer.init(allocator);
        }

        return ParallelRenderSystem{
            .allocator = allocator,
            .thread_pool = thread_pool,
            .command_buffers = command_buffers,
            .main_command_buffer = RenderCommandBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *ParallelRenderSystem) void {
        for (self.command_buffers) |*buffer| {
            buffer.deinit();
        }
        self.allocator.free(self.command_buffers);
        self.main_command_buffer.deinit();
        self.thread_pool.deinit();
    }

    pub fn beginFrame(self: *ParallelRenderSystem) void {
        for (self.command_buffers) |*buffer| {
            buffer.clear();
        }
        self.main_command_buffer.clear();
    }

    pub fn getCommandBuffer(self: *ParallelRenderSystem, thread_id: u32) *RenderCommandBuffer {
        if (thread_id < self.command_buffers.len) {
            return &self.command_buffers[thread_id];
        }
        return &self.main_command_buffer;
    }

    pub fn submitParallelWork(self: *ParallelRenderSystem, comptime WorkData: type, work_items: []WorkData, work_func: *const fn (*WorkData, *RenderCommandBuffer) void) !void {
        const items_per_thread = (work_items.len + self.thread_pool.getWorkerCount() - 1) / self.thread_pool.getWorkerCount();

        var completion_events = try self.allocator.alloc(std.Thread.ResetEvent, self.thread_pool.getWorkerCount());
        defer self.allocator.free(completion_events);

        for (completion_events) |*event| {
            event.* = std.Thread.ResetEvent{};
        }

        var thread_id: u32 = 0;
        var start_index: usize = 0;

        while (start_index < work_items.len and thread_id < self.thread_pool.getWorkerCount()) {
            const end_index = @min(start_index + items_per_thread, work_items.len);
            const thread_work_items = work_items[start_index..end_index];

            const work_data = try self.allocator.create(ParallelWorkData(WorkData));
            work_data.* = ParallelWorkData(WorkData){
                .work_items = thread_work_items,
                .work_func = work_func,
                .command_buffer = &self.command_buffers[thread_id],
                .allocator = self.allocator,
            };

            const job = Job{
                .function = ParallelWorkData(WorkData).execute,
                .data = work_data,
                .priority = .normal,
                .completion_event = &completion_events[thread_id],
            };

            try self.thread_pool.submitJob(job);

            start_index = end_index;
            thread_id += 1;
        }

        // Wait for all jobs to complete
        for (completion_events[0..thread_id]) |*event| {
            event.wait();
        }
    }

    fn ParallelWorkData(comptime WorkData: type) type {
        return struct {
            work_items: []WorkData,
            work_func: *const fn (*WorkData, *RenderCommandBuffer) void,
            command_buffer: *RenderCommandBuffer,
            allocator: std.mem.Allocator,

            const Self = @This();

            fn execute(data: *anyopaque) void {
                const self = @as(*Self, @ptrCast(@alignCast(data)));
                defer self.allocator.destroy(self);

                for (self.work_items) |*item| {
                    self.work_func(item, self.command_buffer);
                }
            }
        };
    }

    pub fn executeCommandBuffers(self: *ParallelRenderSystem, render_pass: *renderer.RenderPass) void {
        // Execute main command buffer first
        self.main_command_buffer.execute(render_pass);

        // Execute all thread command buffers
        for (self.command_buffers) |*buffer| {
            buffer.execute(render_pass);
        }
    }
};

// Job system for general-purpose parallel work
pub const JobSystem = struct {
    allocator: std.mem.Allocator,
    thread_pool: ThreadPool,

    pub fn init(allocator: std.mem.Allocator, thread_count: ?u32) !JobSystem {
        const worker_count = thread_count orelse @max(1, std.Thread.getCpuCount() catch 4);

        return JobSystem{
            .allocator = allocator,
            .thread_pool = try ThreadPool.init(allocator, worker_count, 2000),
        };
    }

    pub fn deinit(self: *JobSystem) void {
        self.thread_pool.deinit();
    }

    pub fn schedule(self: *JobSystem, comptime func: anytype, args: anytype, priority: JobPriority) !void {
        const work_data = try self.allocator.create(@TypeOf(args));
        work_data.* = args;

        const job = Job{
            .function = struct {
                fn execute(data: *anyopaque) void {
                    const typed_data = @as(*@TypeOf(args), @ptrCast(@alignCast(data)));
                    defer self.allocator.destroy(typed_data);
                    @call(.auto, func, typed_data.*);
                }
            }.execute,
            .data = work_data,
            .priority = priority,
        };

        try self.thread_pool.submitJob(job);
    }

    pub fn scheduleWithCallback(self: *JobSystem, comptime func: anytype, args: anytype, priority: JobPriority, completion_callback: ?*const fn () void) !void {
        _ = completion_callback; // TODO: Implement completion callbacks
        try self.schedule(func, args, priority);
    }

    pub fn parallelFor(self: *JobSystem, comptime WorkItem: type, items: []WorkItem, comptime work_func: fn (*WorkItem) void) !void {
        const items_per_chunk = @max(1, items.len / self.thread_pool.getWorkerCount());
        var start_index: usize = 0;

        var completion_events = try self.allocator.alloc(std.Thread.ResetEvent, self.thread_pool.getWorkerCount());
        defer self.allocator.free(completion_events);

        for (completion_events) |*event| {
            event.* = std.Thread.ResetEvent{};
        }

        var jobs_submitted: u32 = 0;

        while (start_index < items.len) {
            const end_index = @min(start_index + items_per_chunk, items.len);
            const chunk = items[start_index..end_index];

            const work_data = try self.allocator.create(ParallelForData(WorkItem));
            work_data.* = ParallelForData(WorkItem){
                .items = chunk,
                .work_func = work_func,
                .allocator = self.allocator,
            };

            const job = Job{
                .function = ParallelForData(WorkItem).execute,
                .data = work_data,
                .priority = .normal,
                .completion_event = &completion_events[jobs_submitted],
            };

            try self.thread_pool.submitJob(job);

            start_index = end_index;
            jobs_submitted += 1;
        }

        // Wait for all chunks to complete
        for (completion_events[0..jobs_submitted]) |*event| {
            event.wait();
        }
    }

    fn ParallelForData(comptime WorkItem: type) type {
        return struct {
            items: []WorkItem,
            work_func: fn (*WorkItem) void,
            allocator: std.mem.Allocator,

            const Self = @This();

            fn execute(data: *anyopaque) void {
                const self = @as(*Self, @ptrCast(@alignCast(data)));
                defer self.allocator.destroy(self);

                for (self.items) |*item| {
                    self.work_func(item);
                }
            }
        };
    }
};

// High-level threading utilities
pub fn getOptimalThreadCount() u32 {
    return @max(1, std.Thread.getCpuCount() catch 4);
}

pub fn createJobSystem(allocator: std.mem.Allocator) !JobSystem {
    return JobSystem.init(allocator, null);
}

pub fn createRenderSystem(allocator: std.mem.Allocator, thread_count: ?u32) !ParallelRenderSystem {
    const worker_count = thread_count orelse @max(1, getOptimalThreadCount() - 1); // Leave one core for main thread
    return ParallelRenderSystem.init(allocator, worker_count);
}

// Test function
test "threading system basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test thread pool
    var pool = try ThreadPool.init(allocator, 2, 100);
    defer pool.deinit();

    var counter = std.atomic.Value(i32).init(0);

    const TestData = struct {
        counter: *std.atomic.Value(i32),
    };

    const test_data = TestData{ .counter = &counter };

    const job = Job{
        .function = struct {
            fn work(data: *anyopaque) void {
                const typed_data = @as(*TestData, @ptrCast(@alignCast(data)));
                _ = typed_data.counter.fetchAdd(1, .seq_cst);
            }
        }.work,
        .data = @constCast(&test_data),
        .priority = .normal,
    };

    try pool.submitJob(job);
    pool.waitForAll();

    try std.testing.expect(counter.load(.seq_cst) == 1);

    // Test job system
    var job_system = try JobSystem.init(allocator, 2);
    defer job_system.deinit();

    var test_values = [_]i32{ 1, 2, 3, 4, 5 };
    try job_system.parallelFor(i32, &test_values, struct {
        fn doubleValue(value: *i32) void {
            value.* *= 2;
        }
    }.doubleValue);

    try std.testing.expect(test_values[0] == 2);
    try std.testing.expect(test_values[4] == 10);
}