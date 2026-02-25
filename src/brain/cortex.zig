const std = @import("std");
const neurons = @import("neuron.zig");

pub const Synapse = struct {
    index: u16,
    target: f32,
    weight: f32,
};

// Neuro layout
// 0-255 - sensory inputs (RS)
// 256-1600 - inhibotry (FS)
// 1600-2400 - excitory (RS)

pub const Cortex = struct {
    neuron: []neurons.Neuron,
    current_buffer: []f32,

    synapse_start_index: []u32,
    synapse_count: []u16,

    synapse_weight: []f32,
    synapse_target: []u16,

    spike_list: []u16,
    spike_count: usize,

    allocator: std.mem.Allocator,

    dopamine: f32,
    serotonin: f32,
    noradrenaline: f32,
    ih_gain: f32,
    exe_gain: f32,
    noise_floor: f32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const neuron = try allocator.alloc(neurons.Neuron, 2048);
        const synapse_start = try allocator.alloc(u32, 2048);
        const current_buffer = try allocator.alloc(f32, 2048);
        const synapse_count = try allocator.alloc(u16, 2048);
        const spike_list = try allocator.alloc(u16, 2048);

        for (neuron, 0..2048) |*n, i| {
            if (i <= 255) {
                n.* = neurons.Neuron.init(.SpikingRegular);
            }

            if (i > 255 and i <= 1600) {
                n.* = neurons.Neuron.init(.SpikingRegular);
            }

            if (i > 1600) {
                n.* = neurons.Neuron.init(.SpikingFast);
            }
        }

        return Self{
            .neuron = neuron,
            .synapse_start_index = synapse_start,
            .current_buffer = current_buffer,
            .synapse_count = synapse_count,
            .allocator = allocator,
            .synapse_weight = &[_]f32{},
            .synapse_target = &[_]u16{},
            .spike_list = spike_list,
            .spike_count = 0,
            .serotonin = 0.0,
            .noradrenaline = 0.0,
            .exe_gain = 0.0,
            .ih_gain = 0.0,
            .noise_floor = 0.0,
            .dopamine = 0.0,
        };
    }

    pub fn update(self: *Self) void {
        // }

        self.dopamine = 1.0;
        self.serotonin = 1.0;

        self.exe_gain = 1.0 + (self.dopamine * 1.0);
        self.ih_gain = 1.0 + (self.serotonin * 3.0);
        self.noise_floor = self.noradrenaline * 5.0;

        // std.debug.print("current buffer at frame 0 {d:.2}\n", .{self.current_buffer[0]});
        for (0..self.neuron.len) |i| {
            // std.debug.print("input for value of neuron v {d:.2}\n", .{self.neuron[i].v});
            self.neuron[i].update(self.current_buffer[i], self.noise_floor, 1.0);

            self.current_buffer[i] = 0.0;

            if (self.neuron[i].fired) {
                self.spike_list[self.spike_count] = @intCast(i);
                self.spike_count += 1;
            }
        }
    }

    pub fn setInputs(self: *Self, index: usize, input_votage: f32) void {
        if (index >= 256) return;
        const amps = input_votage * 50.0;
        self.current_buffer[index] += amps;
        // if (amps > 0.0) {
        //     std.debug.print("curret buffer {d:.2}\n", .{self.current_buffer[index]});
        // }
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.neuron);
        self.allocator.free(self.current_buffer);
        self.allocator.free(self.synapse_start_index);
        self.allocator.free(self.synapse_count);
        self.allocator.free(self.spike_list);

        if (self.synapse_target.len > 0) self.allocator.free(self.synapse_target);
        if (self.synapse_weight.len > 0) self.allocator.free(self.synapse_weight);
    }
};

test "neuron before and after init" {
    var ta = std.heap.DebugAllocator(.{}).init;
    defer _ = ta.deinit();

    const alloc = ta.allocator();

    var c = try Cortex.init(alloc);
    defer c.deinit();

    c.update();
}
