//! term_sig.zig – Terminal visualization for mod-e neuromorphic simulator.
//!
//! Layout (adaptive to terminal size):
//!   ┌─ Spike Raster ──────────────────────────┐ ┌─ STATS ──────────┐
//!   │ S █·██·····█·  · · ·█·····█ · ·· ·█·   │ │ Tick   00012345  │
//!   │ M ·█·····██··  █·██·····██ ·  ·  ·      │ │ Spikes      42   │
//!   │ O ···█·····█·  ··  ·  ·   ·  ·  ·       │ │ Rate    2.05%    │
//!   ├─ Voltage Heatmap (2048 neurons) ─────────┤ │ AvgV  -61.3 mV   │
//!   │ [64×32 colored █ blocks, blue→red]       │ │ AvgW   1.843     │
//!   └───────────────────────────────────────────┘ │ Total  00045612  │
//!   ┌─ Neurotransmitter Proxies ─────────────────┐ │ Trace   +12.34  │
//!   │ Dopamine  [████████░░░░] 40.0%             │ │ Syns   72960    │
//!   │ Serotonin [████░░░░░░░░] 20.0%             │ │                  │
//!   │ NorAdr.   [██░░░░░░░░░░] 10.0%             │ │ [q] quit         │
//!   └────────────────────────────────────────────┘ └──────────────────┘
//!
//! Key bindings: q / Ctrl-C → quit.

const std = @import("std");
const vaxis = @import("vaxis");

const brain_mod = @import("brain/brain.zig");
const cortex_mod = @import("brain/cortex.zig");
const plasticity_mod = @import("brain/plasticity.zig");

const NEURON_COUNT: usize = 2048;
const SENSORY_END: usize = 256;
const MIDDLE_END: usize = 1600;
const RASTER_DEPTH: usize = 80;
const RATE_WINDOW: usize = 60;

const RasterFrame = struct {
    bits: [256]u8 = [_]u8{0} ** 256,
    spike_count: u16 = 0,

    fn set(self: *RasterFrame, n: usize) void {
        self.bits[n >> 3] |= @as(u8, 1) << @intCast(n & 7);
    }

    fn get(self: *const RasterFrame, n: usize) bool {
        return ((self.bits[n >> 3] >> @intCast(n & 7)) & 1) != 0;
    }

    fn anyInRange(self: *const RasterFrame, lo: usize, hi: usize) bool {
        const cap = @min(hi, NEURON_COUNT);
        for (lo..cap) |i| if (self.get(i)) return true;
        return false;
    }

    fn clear(self: *RasterFrame) void {
        @memset(&self.bits, 0);
        self.spike_count = 0;
    }
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn term_sig(allocator: std.mem.Allocator) !void {
    var b = try brain_mod.Brain.init(allocator);
    var c = try cortex_mod.Cortex.init(allocator);
    var p = try plasticity_mod.Plasticity.init(allocator, 200_000);
    defer b.deinit();
    defer c.deinit();
    defer p.deinit();

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    try wire(&b, prng.random());
    try b.bake(&c, &p);

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    var raster: [RASTER_DEPTH]RasterFrame = [_]RasterFrame{.{}} ** RASTER_DEPTH;
    var raster_head: usize = 0; // next-write slot index

    var tick: u64 = 0;
    var total_spikes: u64 = 0;
    var recent_spikes: [RATE_WINDOW]u16 = [_]u16{0} ** RATE_WINDOW;
    var recent_pos: usize = 0;

    const tick_ns: u64 = 20 * std.time.ns_per_ms; // 50 Hz target

    while (true) {
        const t0: i128 = std.time.nanoTimestamp();

        _ = frame_arena.reset(.retain_capacity);
        const fa = frame_arena.allocator();

        while (loop.tryEvent()) |ev| {
            switch (ev) {
                .key_press => |key| {
                    if (key.matches('q', .{}) or
                        key.matches('c', .{ .ctrl = true }))
                    {
                        return;
                    }
                },
                .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            }
        }

        for (0..8) |i| c.setInputs(i, prng.random().float(f32));

        c.update();

        const slot = raster_head % RASTER_DEPTH;
        raster[slot].clear();
        var step_spikes: u16 = 0;
        for (0..NEURON_COUNT) |i| {
            if (c.neuron[i].fired) {
                raster[slot].set(i);
                step_spikes += 1;
            }
        }
        raster[slot].spike_count = step_spikes;
        raster_head += 1;

        recent_spikes[recent_pos % RATE_WINDOW] = step_spikes;
        recent_pos += 1;
        total_spikes += step_spikes;

        const win = vx.window();
        win.clear();

        if (win.width > 20 and win.height > 6) {
            renderUI(win, fa, &c, &p, &raster, raster_head, tick, total_spikes, &recent_spikes);
        }

        try vx.render(tty.writer());

        tick += 1;

        const elapsed: u64 = @intCast(@max(std.time.nanoTimestamp() - t0, 0));
        if (elapsed < tick_ns) std.Thread.sleep(tick_ns - elapsed);
    }
}

fn renderUI(
    win: vaxis.Window,
    fa: std.mem.Allocator,
    c: *cortex_mod.Cortex,
    p: *plasticity_mod.Plasticity,
    raster: *const [RASTER_DEPTH]RasterFrame,
    raster_head: usize,
    tick: u64,
    total_spikes: u64,
    recent_spikes: *const [RATE_WINDOW]u16,
) void {
    const W = win.width;
    const H = win.height;

    const stats_w: u16 = @min(22, W / 4);
    const vis_w: u16 = W -| stats_w -| 1;

    const neuro_h: u16 = 5;
    const avail_h: u16 = H -| 1 -| neuro_h;
    const raster_h: u16 = avail_h / 2;
    const heatmap_h: u16 = avail_h -| raster_h;

    const title = std.fmt.allocPrint(fa, " mod-e Neural Monitor  tick={d}", .{tick}) catch " mod-e";
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title,
        .style = .{ .bold = true, .fg = .{ .rgb = [_]u8{ 100, 200, 255 } } },
    }}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

    if (raster_h >= 3) {
        const panel = win.child(.{
            .x_off = 0,
            .y_off = 1,
            .width = vis_w,
            .height = raster_h,
            .border = .{ .where = .all, .glyphs = .single_rounded },
        });
        drawRaster(panel, raster, raster_head);
    }

    if (heatmap_h >= 3) {
        const panel = win.child(.{
            .x_off = 0,
            .y_off = 1 + raster_h,
            .width = vis_w,
            .height = heatmap_h,
            .border = .{ .where = .all, .glyphs = .single_rounded },
        });
        drawHeatmap(panel, c);
    }

    if (neuro_h >= 3) {
        const y: u16 = 1 + raster_h + heatmap_h;
        if (y + neuro_h <= H) {
            const panel = win.child(.{
                .x_off = 0,
                .y_off = y,
                .width = vis_w,
                .height = neuro_h,
                .border = .{ .where = .all, .glyphs = .single_rounded },
            });
            drawNeuro(panel, fa, c, p, recent_spikes);
        }
    }

    if (stats_w >= 4) {
        const panel = win.child(.{
            .x_off = vis_w + 1,
            .y_off = 0,
            .width = stats_w,
            .height = H,
            .border = .{ .where = .all, .glyphs = .single_rounded },
        });
        drawStats(panel, fa, c, p, tick, total_spikes, recent_spikes);
    }
}

fn drawRaster(
    win: vaxis.Window,
    raster: *const [RASTER_DEPTH]RasterFrame,
    raster_head: usize,
) void {
    const iw: usize = win.width;
    const ih: usize = win.height;
    if (ih == 0 or iw < 3) return;

    const data_cols: usize = @min(iw -| 1, RASTER_DEPTH);
    const data_rows: usize = ih;
    const npr: usize = NEURON_COUNT / @max(data_rows, 1); // neurons-per-row

    for (0..data_cols) |ci| {
        const age = data_cols - ci; // 1 = newest
        const fi = (raster_head + RASTER_DEPTH - age) % RASTER_DEPTH;
        const frame = &raster[fi];

        for (0..data_rows) |ri| {
            const n_lo = ri * npr;
            const n_hi = n_lo + npr;
            const fired = frame.anyInRange(n_lo, n_hi);

            const band: vaxis.Color = if (n_lo < SENSORY_END)
                .{ .rgb = [_]u8{ 60, 220, 60 } } // sensory  → green
            else if (n_lo < MIDDLE_END)
                .{ .rgb = [_]u8{ 60, 130, 255 } } // middle   → blue
            else
                .{ .rgb = [_]u8{ 255, 210, 40 } }; // output   → yellow

            win.writeCell(@intCast(ci + 1), @intCast(ri), .{
                .char = .{ .grapheme = if (fired) "█" else "·", .width = 1 },
                .style = .{ .fg = if (fired) band else .{ .rgb = [_]u8{ 30, 30, 40 } } },
            });
        }
    }

    const s_row: usize = 0;
    const m_row: usize = SENSORY_END / @max(npr, 1);
    const o_row: usize = MIDDLE_END / @max(npr, 1);

    bandLabel(win, 0, @intCast(@min(s_row, ih -| 1)), "S", .{ .rgb = [_]u8{ 60, 220, 60 } });
    if (m_row < ih)
        bandLabel(win, 0, @intCast(m_row), "M", .{ .rgb = [_]u8{ 60, 130, 255 } });
    if (o_row < ih)
        bandLabel(win, 0, @intCast(o_row), "O", .{ .rgb = [_]u8{ 255, 210, 40 } });
}

fn bandLabel(win: vaxis.Window, col: u16, row: u16, g: []const u8, color: vaxis.Color) void {
    win.writeCell(col, row, .{
        .char = .{ .grapheme = g, .width = 1 },
        .style = .{ .fg = color, .bold = true },
    });
}

fn drawHeatmap(win: vaxis.Window, c: *cortex_mod.Cortex) void {
    const iw: usize = win.width;
    const ih: usize = win.height;
    if (ih == 0 or iw == 0) return;

    const total_cells: usize = iw * ih;
    const npc: usize = @max(NEURON_COUNT / total_cells, 1);

    var ni: usize = 0;
    for (0..ih) |row| {
        for (0..iw) |col| {
            if (ni >= NEURON_COUNT) {
                win.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                });
                continue;
            }
            const end = @min(ni + npc, NEURON_COUNT);
            var sum_v: f32 = 0.0;
            var any_fired = false;
            for (ni..end) |k| {
                sum_v += c.neuron[k].v;
                if (c.neuron[k].fired) any_fired = true;
            }
            const avg_v = sum_v / @as(f32, @floatFromInt(end - ni));
            ni = end;

            win.writeCell(@intCast(col), @intCast(row), .{
                .char = .{ .grapheme = "█", .width = 1 },
                .style = .{ .fg = voltageToColor(avg_v, any_fired) },
            });
        }
    }
}

fn drawNeuro(
    win: vaxis.Window,
    fa: std.mem.Allocator,
    c: *cortex_mod.Cortex,
    p: *plasticity_mod.Plasticity,
    recent_spikes: *const [RATE_WINDOW]u16,
) void {
    const iw: usize = win.width;
    if (win.height < 3 or iw < 10) return;

    var dopa_sum: f32 = 0.0;
    var dopa_n: usize = 0;
    for (p.eligibility_traces) |t| {
        if (t > 0.0) {
            dopa_sum += t;
            dopa_n += 1;
        }
    }
    const dopa: f32 = if (dopa_n > 0)
        @min(dopa_sum / (@as(f32, @floatFromInt(dopa_n)) * 2.0), 1.0)
    else
        0.0;

    var recent_total: u32 = 0;
    for (recent_spikes) |s| recent_total += s;
    const avg_rate = @as(f32, @floatFromInt(recent_total)) /
        (@as(f32, RATE_WINDOW) * @as(f32, NEURON_COUNT));
    const serotonin: f32 = @max(0.0, 1.0 - avg_rate * 50.0);

    var nor_sum: f32 = 0.0;
    for (c.current_buffer) |cur| nor_sum += @abs(cur);
    const noradrenaline: f32 = @min(nor_sum / (@as(f32, NEURON_COUNT) * 5.0), 1.0);

    const bar_w: usize = @max(iw -| 13, 2);
    drawBar(win, fa, 0, "Dopamine ", dopa, bar_w, .{ .rgb = [_]u8{ 80, 180, 255 } });
    drawBar(win, fa, 1, "Serotonin", serotonin, bar_w, .{ .rgb = [_]u8{ 80, 255, 140 } });
    drawBar(win, fa, 2, "NorAdr.  ", noradrenaline, bar_w, .{ .rgb = [_]u8{ 255, 170, 50 } });
}

fn drawBar(
    win: vaxis.Window,
    fa: std.mem.Allocator,
    row: u16,
    label: []const u8,
    value: f32,
    bar_w: usize,
    color: vaxis.Color,
) void {
    const clamped = @min(@max(value, 0.0), 1.0);
    const filled: usize = @intFromFloat(@as(f32, @floatFromInt(bar_w)) * clamped);

    var col: u16 = 0;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = label,
        .style = .{ .fg = .{ .rgb = [_]u8{ 160, 160, 160 } } },
    }}, .{ .row_offset = row, .col_offset = col, .wrap = .none });
    col += @intCast(label.len);

    win.writeCell(col, row, .{
        .char = .{ .grapheme = "[", .width = 1 },
        .style = .{ .fg = .{ .rgb = [_]u8{ 90, 90, 90 } } },
    });
    col += 1;

    for (0..bar_w) |i| {
        const is_fill = i < filled;
        win.writeCell(col + @as(u16, @intCast(i)), row, .{
            .char = .{ .grapheme = if (is_fill) "█" else "░", .width = 1 },
            .style = .{ .fg = if (is_fill) color else .{ .rgb = [_]u8{ 40, 40, 50 } } },
        });
    }
    col += @intCast(bar_w);

    const pct = std.fmt.allocPrint(fa, "] {d:4.1}%", .{clamped * 100.0}) catch "]";
    _ = win.print(&[_]vaxis.Segment{.{
        .text = pct,
        .style = .{ .fg = .{ .rgb = [_]u8{ 160, 160, 160 } } },
    }}, .{ .row_offset = row, .col_offset = col, .wrap = .none });
}

fn drawStats(
    win: vaxis.Window,
    fa: std.mem.Allocator,
    c: *cortex_mod.Cortex,
    p: *plasticity_mod.Plasticity,
    tick: u64,
    total_spikes: u64,
    recent_spikes: *const [RATE_WINDOW]u16,
) void {
    const gray: vaxis.Color = .{ .rgb = [_]u8{ 170, 170, 170 } };
    var r: u16 = 0;

    statPrint(win, r, "STATS", .{ .bold = true, .fg = gray });
    r += 1;

    statFmt(win, fa, r, "Tick", "{d}", .{tick}, .{ .rgb = [_]u8{ 200, 200, 200 } });
    r += 1;

    var cur_spikes: u32 = 0;
    for (0..NEURON_COUNT) |i| if (c.neuron[i].fired) {
        cur_spikes += 1;
    };
    statFmt(win, fa, r, "Spikes", "{d}", .{cur_spikes}, .{ .rgb = [_]u8{ 80, 230, 80 } });
    r += 1;

    var recent_total: u32 = 0;
    for (recent_spikes) |s| recent_total += s;
    const rate = @as(f32, @floatFromInt(recent_total)) /
        (@as(f32, RATE_WINDOW) * @as(f32, NEURON_COUNT)) * 100.0;
    const rate_color: vaxis.Color = if (rate > 10.0)
        .{ .rgb = [_]u8{ 255, 80, 80 } }
    else
        .{ .rgb = [_]u8{ 80, 180, 255 } };
    statFmt(win, fa, r, "Rate", "{d:.2}%", .{rate}, rate_color);
    r += 1;

    var avg_v: f32 = 0.0;
    for (0..NEURON_COUNT) |i| avg_v += c.neuron[i].v;
    avg_v /= @as(f32, NEURON_COUNT);
    statFmt(win, fa, r, "AvgV", "{d:.1}mV", .{avg_v}, .{ .rgb = [_]u8{ 150, 150, 255 } });
    r += 1;

    if (c.synapse_weight.len > 0) {
        var sum_w: f32 = 0.0;
        for (c.synapse_weight) |w| sum_w += w;
        const avg_w = sum_w / @as(f32, @floatFromInt(c.synapse_weight.len));
        statFmt(win, fa, r, "AvgW", "{d:.3}", .{avg_w}, .{ .rgb = [_]u8{ 255, 190, 80 } });
        r += 1;
    }

    statFmt(win, fa, r, "Total", "{d}", .{total_spikes}, .{ .rgb = [_]u8{ 140, 140, 200 } });
    r += 1;

    if (p.eligibility_traces.len > 0) {
        var tr_sum: f32 = 0.0;
        for (p.eligibility_traces) |t| tr_sum += t;
        statFmt(win, fa, r, "Trace", "{d:.2}", .{tr_sum}, .{ .rgb = [_]u8{ 190, 80, 255 } });
        r += 1;
    }

    statFmt(win, fa, r, "Syns", "{d}", .{c.synapse_weight.len}, .{ .rgb = [_]u8{ 120, 120, 120 } });

    if (win.height > 2) {
        statPrint(win, win.height -| 1, "[q] quit", .{ .fg = .{ .rgb = [_]u8{ 80, 80, 80 } } });
    }
}

fn statFmt(
    win: vaxis.Window,
    fa: std.mem.Allocator,
    row: u16,
    label: []const u8,
    comptime fmt: []const u8,
    args: anytype,
    color: vaxis.Color,
) void {
    const val_str = std.fmt.allocPrint(fa, fmt, args) catch "?";
    const line = std.fmt.allocPrint(fa, "{s} {s}", .{ label, val_str }) catch label;
    statPrint(win, row, line, .{ .fg = color });
}

fn statPrint(win: vaxis.Window, row: u16, text: []const u8, style: vaxis.Style) void {
    _ = win.print(&[_]vaxis.Segment{.{ .text = text, .style = style }}, .{ .row_offset = row, .col_offset = 1, .wrap = .none });
}

fn voltageToColor(v: f32, fired: bool) vaxis.Color {
    if (fired) return .{ .rgb = [_]u8{ 255, 255, 255 } };

    // Normalise to [0, 1]:  −65 mV → 0,  +30 mV → 1.
    const norm: f32 = @min(@max((v + 65.0) / 95.0, 0.0), 1.0);

    if (norm < 0.25) {
        const t = norm / 0.25;
        return .{ .rgb = [_]u8{
            0,
            0,
            @as(u8, @intFromFloat(40.0 + t * 100.0)),
        } };
    } else if (norm < 0.5) {
        const t = (norm - 0.25) / 0.25;
        return .{ .rgb = [_]u8{
            0,
            @as(u8, @intFromFloat(t * 180.0)),
            @as(u8, @intFromFloat(140.0 + t * 80.0)),
        } };
    } else if (norm < 0.75) {
        const t = (norm - 0.5) / 0.25;
        return .{ .rgb = [_]u8{
            @as(u8, @intFromFloat(t * 255.0)),
            @as(u8, @intFromFloat(180.0 + t * 75.0)),
            @as(u8, @intFromFloat(220.0 - t * 180.0)),
        } };
    } else {
        const t = (norm - 0.75) / 0.25;
        return .{ .rgb = [_]u8{
            255,
            @as(u8, @intFromFloat(255.0 - t * 200.0)),
            0,
        } };
    }
}

fn wire(b: *brain_mod.Brain, random: std.Random) !void {
    for (0..2048) |i| {
        if (i <= 255) {
            for (0..20) |_| {
                const dst = random.intRangeAtMost(u16, 256, 1919);
                try b.connect(@intCast(i), dst, random.float(f32) * 2.0 + 1.0);
            }
        } else if (i <= 1919) {
            const inhibitory = i > 1600;
            for (0..40) |_| {
                const dst: u16 = if (random.float(f32) > 0.1)
                    random.intRangeAtMost(u16, 256, 1919)
                else
                    random.intRangeAtMost(u16, 1920, 2047);
                const w: f32 = if (inhibitory)
                    -(random.float(f32) * 2.0 + 1.0)
                else
                    random.float(f32) * 2.0 + 1.0;
                try b.connect(@intCast(i), dst, w);
            }
        }
    }
}
