const std = @import("std");
const cortexLib = @import("cortex.zig");
const plasticity = @import("plasticity.zig");

const Synapse = struct {
    weight: f32,
    target: u16,
    source: u16,
};

pub const Brain = struct {
    connections: std.ArrayList(Synapse),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const conn = try std.ArrayList(Synapse).initCapacity(allocator, 200000);

        return Self{
            .connections = conn,
            .allocator = allocator,
        };
    }

    pub fn connect(self: *Self, src: u16, dst: u16, weight: f32) !void {
        try self.connections.append(self.allocator, .{
            .source = src,
            .target = dst,
            .weight = weight,
        });
    }

    pub fn bake(self: *Self, cortex: *cortexLib.Cortex, plastic: *plasticity.Plasticity) !void {
        std.sort.block(Synapse, self.connections.items, .{}, lessThan);

        const total_wires = self.connections.items.len;

        @memset(cortex.synapse_start_index, 0);
        @memset(cortex.synapse_count, 0);

        var current_source: u16 = 0;
        var run_count: u16 = 0;

        if (cortex.synapse_target.len > 0) cortex.allocator.free(cortex.synapse_target);
        if (cortex.synapse_weight.len > 0) cortex.allocator.free(cortex.synapse_weight);

        cortex.synapse_target = try self.allocator.alloc(u16, total_wires);
        cortex.synapse_weight = try self.allocator.alloc(f32, total_wires);

        plastic.eligibility_traces = try self.allocator.alloc(f32, total_wires);
        plastic.last_spike_times = try self.allocator.alloc(u64, 2048);

        for (self.connections.items, 0..) |conn, i| {
            cortex.synapse_weight[i] = conn.weight;
            cortex.synapse_target[i] = conn.target;

            if (current_source != conn.source) {
                cortex.synapse_count[current_source] = 0;

                current_source = conn.source;

                run_count = 0;
            }

            run_count += 1;

            if (current_source < 2048) {
                cortex.synapse_count[current_source] = run_count;
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.connections.deinit(self.allocator);
    }

    fn lessThan(ctx: @TypeOf(.{}), rhs: Synapse, lhs: Synapse) bool {
        _ = ctx;
        return rhs.source < lhs.source;
    }
};
