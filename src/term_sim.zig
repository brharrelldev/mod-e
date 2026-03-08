const std = @import("std");
const cortex = @import("brain/cortex.zig");
const brain = @import("brain/brain.zig");
const plasticity = @import("brain/plasticity.zig");

pub fn term_sim(allocator: std.mem.Allocator) !void {
    var b = try brain.Brain.init(allocator);
    var c = try cortex.Cortex.init(allocator);
    var p = try plasticity.Plasticity.init(allocator, 200000);

    defer b.deinit();
    c.deinit();

    defer c.deinit();

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    try wire(&b, prng.random());
    try b.bake(&c, &p);

    while (true) {
        std.log.info("simulator loop\n", .{});
    }
}

fn wire(b: *brain.Brain, random: std.Random) !void {
    for (0..2048) |i| {
        if (i <= 255) {
            const num_connections = 20;

            for (0..num_connections) |_| {
                const dst = random.intRangeAtMost(u16, 256, 1919);
                const weight = random.float(f32) * 2.0 + 1.0;

                try b.connect(@intCast(i), dst, weight);
            }
        } else if (i <= 1919) {
            const num_connections = 40;

            const is_inhibitory = (i > 1600);

            for (0..num_connections) |_| {
                var dst: u16 = 0;

                if (random.float(f32) > 0.10) {
                    dst = random.intRangeAtMost(u16, 256, 1919);
                } else {
                    dst = random.intRangeAtMost(u16, 1920, 2047);
                }

                var weight: f32 = 0.0;

                if (is_inhibitory) {
                    weight = -(random.float(f32) * 2.0 + 1.0);
                } else {
                    weight = random.float(f32) * 2.0 + 1.0;
                }

                try b.connect(@intCast(i), dst, weight);
            }
        } else {}
    }
}
