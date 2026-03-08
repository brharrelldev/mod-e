const std = @import("std");
const raylib = @import("raylib");
const robot = @import("robot/robot.zig");
const clap = @import("clap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'm',
            .names = .{ .short = 'm', .long = "mode" },
            .takes_value = .one,
        },
    };

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);

    _ = iter.next();

    var diag = clap.Diagnostic{};

    var parsers = clap.streaming.Clap(u8, std.process.ArgIterator){
        .iter = &iter,
        .params = &params,
        .diagnostic = &diag,
    };

    while (parsers.next() catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => std.debug.print("Help\n", .{}),
            'm' => {
                const value = arg.value orelse "text";

                if (!std.mem.eql(u8, value, "text") and !std.mem.eql(u8, value, "robot")) {
                    std.log.err("value can be either 'text' or 'robot'\n", .{});
                } else {
                    if (std.mem.eql(u8, value, "text")) {
                        const term_sig = @import("term_sim.zig");

                        try term_sig.term_sim(allocator);
                    }

                    if (std.mem.eql(u8, value, "robot")) {
                        const rl = @import("robot_sig.zig");

                        rl.robot_loop();
                    }
                }
            },

            else => unreachable,
        }
    }
}
