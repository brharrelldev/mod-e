const raylib = @import("raylib");
const robot = @import("robot/robot.zig");

pub fn robot_loop() void {
    var r = robot.Robot.init();
    const cf = raylib.ConfigFlags{
        .window_highdpi = true,
    };

    raylib.setConfigFlags(cf);

    raylib.initWindow(1200, 800, "mod-e");

    defer raylib.closeWindow();

    while (!raylib.windowShouldClose()) {
        raylib.beginDrawing();

        defer raylib.endDrawing();

        raylib.clearBackground(.black);

        r.draw();
    }
}
