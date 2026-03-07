const std = @import("std");
const raylib = @import("raylib");

pub const Robot = struct {
    eyes: [2]raylib.Rectangle,
    face: raylib.Rectangle,
    mouth: raylib.Rectangle,
    const Self = @This();

    pub fn init() Self {
        var eyes: [2]raylib.Rectangle = undefined;

        eyes[0] = .{
            .height = 100,
            .width = 100,
            .x = 420,
            .y = 200,
        };

        eyes[1] = .{
            .height = 100,
            .width = 100,
            .x = 550,
            .y = 200,
        };

        const face = raylib.Rectangle{
            .y = 200,
            .width = 400,
            .x = 340,
            .height = 200,
        };

        const mouth = raylib.Rectangle{
            .width = 400,
            .height = 400,
            .x = 300,
            .y = 300,
        };

        return Self{
            .face = face,
            .eyes = eyes,
            .mouth = mouth,
        };
    }

    pub fn draw(self: *Self) void {
        raylib.drawRectangleRec(self.face, .white);
        raylib.drawRectangleRec(self.eyes[0], .blue);
        raylib.drawRectangleRec(self.eyes[1], .blue);
    }
};
