const std = @import("std");
const raylib = @import("raylib");
const robot = @import("robot/robot.zig");
const clap = @import("clap");

const Mode = enum {
    Term,
    Robot,
};

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help
        \\-m, --mode <ANSWER> put in Term or Robot
    );

    const parsers = comptime .{
        .ANSWER = clap.parsers.enumeration(Mode),
    };

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
        .assignment_separators = "=",
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };

    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help", .{});
    if (res.args.mode) |m| {
        switch (m) {
            .Term => {
                const term = @import("term_sig.zig");

                try term.term_sig(init.io, init.environ_map, init.gpa);
            },
            .Robot => {
                std.debug.print("Robot selected\n", .{});
            },
            // else => {
            //     std.debug.print("must be 'Term' or 'Robot'\n", .{});
            // },
        }
        //     if (!std.mem.eql(u8, @tagName(m), "Term") and !std.mem.eql(u8, @tagName(m), "Robot")) {
        //         std.debug.print("value can only be 'Term' or 'Robot'\n", .{});
        //     }
    }
}
