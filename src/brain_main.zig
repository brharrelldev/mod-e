const std = @import("std");
const raylib = @import("raylib");
const robot = @import("robot/robot.zig");
const args = @import("args");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var parser = try args.ArgumentParser.init(allocator, .{
        .version = "0.0.1",
        .name = "mod-e",
    });
    defer parser.deinit();

    try parser.addOption("mode", .{
        .help = "just testing out an option",
        .value_type = .string,
        .choices = &[_][]const u8{ "term", "robot" },
        .env_var = "MODE",
        .required = true,
    });

    var result = try parser.parseProcess();
    defer result.deinit();

    const t = result.getString("mode") orelse "term";

    if (std.mem.eql(u8, t, "term")) {
        const term_sim = @import("term_sim.zig");

        term_sim.term_sim();
    } else {
        std.debug.print("robot placeholder\n", .{});
    }

    // var r = robot.Robot.init();
    // const cf = raylib.ConfigFlags{
    //     .window_highdpi = true,
    // };
    //
    // raylib.setConfigFlags(cf);
    //
    // raylib.initWindow(1200, 800, "mod-e");
    //
    // defer raylib.closeWindow();
    //
    // while (!raylib.windowShouldClose()) {
    //     raylib.beginDrawing();
    //
    //     defer raylib.endDrawing();
    //
    //     raylib.clearBackground(.black);
    //
    //     r.draw();
    // }
}
