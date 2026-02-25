const std = @import("std");

const SpikingTypes = enum {
    SpikingRegular,
    SpikingFast,
};

// Izhikevich Neuro model (2003)
// See: https://www.izhikevich.org/publications/spikes.pdf
// a,b,c,d are personality parameters
// different neuron models tuned to different values
// this simulates Serotonin and Dopamine
pub const Neuron = struct {
    v: f32,
    u: f32,
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    fired: bool,

    const Self = @This();

    pub fn init(st: SpikingTypes) Self {
        const voltage: f32 = -65.0;
        switch (st) {
            // normal spiking (non-bursting)
            // a = 0.02; b = 0.2; c = -65.0; d = 8.0
            .SpikingRegular => {
                return Self{
                    .v = voltage,
                    .a = 0.02,
                    .b = 0.2,
                    .c = -65.0,
                    .d = 8.0,
                    .u = 0.2 * voltage,
                    .fired = false,
                };
            },
            // fast spiking
            // a = 0.1; b = 0.2; c = -65.0; d = 2.0
            .SpikingFast => {
                return Self{
                    .v = voltage,
                    .a = 0.1,
                    .b = 0.2,
                    .c = -65.0,
                    .d = 2.0,
                    .u = 0.2 * voltage,
                    .fired = false,
                };
            },
        }
    }

    pub fn update(self: *Self, i_syn: f32, i_noise: f32, dt: f32) void {
        var I = i_syn + i_noise;

        const v_sq = self.v * self.v;

        const dv = (0.04 * v_sq) + (5.0 * self.v) + 140.0 - self.u + I;
        const du = self.a * ((self.b * self.v) - self.u);

        self.v += (dv * dt);
        self.u += (du * dt);

        if (self.v >= 30.0) {
            self.fired = true;
            self.v = self.c;
            self.u += self.d;
        } else {
            self.fired = false;
        }

        I = 0.0;
    }
};

test "Fast Spiking" {
    const n = Neuron.init(.SpikingFast);

    try std.testing.expectEqual(n.a, 0.1);
}

test "Regular spiking " {
    const n = Neuron.init(.SpikingRegular);

    try std.testing.expectEqual(n.a, 0.2);
}
