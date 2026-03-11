const std = @import("std");

const max_neuron_count: usize = 2048;
const trace_decay_factor: f32 = 0.5;
const tau_plus: f32 = 0.5;
const tau_minus: f32 = -0.5;
const learning_rate: f32 = 1.0;

const aplus: f32 = 0.5;
const aminus: f32 = -0.5;
const euler: f32 = 2.71828;

pub const Plasticity = struct {
    weights: []f32,
    eligibility_traces: []f32,
    pre_indicies: []u16, //row (CSR)
    post_indicies: []u16, //columns (CSS)
    last_spike_times: []u64,
    allocator: std.mem.Allocator,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, connection_count: u32) !Self {
        const eligibility_traces = try allocator.alloc(f32, connection_count);
        const pre_indicies = try allocator.alloc(u16, max_neuron_count);
        const post_indicies = try allocator.alloc(u16, connection_count);
        const last_spike_times = try allocator.alloc(u64, max_neuron_count);

        return Self{
            .weights = &[_]f32{},
            .eligibility_traces = eligibility_traces,
            .pre_indicies = pre_indicies,
            .post_indicies = post_indicies,
            .allocator = allocator,
            .last_spike_times = last_spike_times,
        };
    }
    // FOR EACH pre_synaptic_neuron FROM 0 TO total_neurons:
    //
    //        // Get the time this neuron last fired
    //        pre_spike_time = last_spike_times[pre_synaptic_neuron]
    //
    //        // Find all synapses leaving this neuron using CSR pointers
    //        start_idx = row_pointers[pre_synaptic_neuron]
    //        end_idx = row_pointers[pre_synaptic_neuron + 1]
    //
    //        FOR synapse_idx FROM start_idx TO end_idx:
    //            post_synaptic_neuron = column_indices[synapse_idx]
    //            post_spike_time = last_spike_times[post_synaptic_neuron
    //
    //            // Calculate standard STDP (time difference between pre
    //    and post spikes)
    //            time_delta = post_spike_time - pre_spike_time
    //            stdp_change = calculate_stdp_curve(time_delta)
    //
    //            // CRITICAL DIFFERENCE: We do NOT update the weight.
    //            // We update the eligibility trace.
    //            // Traces also naturally decay over time.
    //            current_trace = eligibility_traces[synapse_idx]
    //            decayed_trace = current_trace * trace_decay_factor
    //
    //            eligibility_traces[synapse_idx] = decayed_trace +
    //    stdp_change
    //
    //
    pub fn update_eligibility(self: *Self) void {
        for (0..max_neuron_count) |n| {
            const pre_spike_time = self.last_spike_times[n];

            const start_idx = self.pre_indicies[n];
            const end_idx = self.pre_indicies[n + 1];

            for (start_idx..end_idx) |si| {
                const post_synpatic = self.post_pointers[si];
                const post_spike_time = self.last_spike_times[post_synpatic];

                const time_delta = post_spike_time - pre_spike_time;

                const stdp_chage = calculate_stdp_curve(time_delta);
                const current_trace = self.eligibility_traces[si];
                const decayed_factor = current_trace * trace_decay_factor;

                self.eligibility_traces[si] = decayed_factor + stdp_chage;
            }
        }
    }

    //    // Phase 2: Apply the Reward (The "R" part)
    //    // This happens at every time step, applying the global reward
    //    the traces.
    //
    //    IF current_reward != 0.0:
    //        FOR synapse_idx FROM 0 TO total_synapses:
    //
    //            trace_value = eligibility_traces[synapse_idx]
    //
    //            // The weight update is proportional to the reward AND
    //    the trace
    //            weight_delta = learning_rate * current_reward *
    //    trace_value
    //
    //            weights[synapse_idx] = weights[synapse_idx] +
    //      weight_delta
    pub fn apply_reward(self: *Self, reward: f32, total_synapses: u16) void {
        if (reward != 0.0) {
            for (0..total_synapses) |i| {
                const trace_value = self.eligibility_traces[i];

                const weight_delta = learning_rate * reward * trace_value;

                self.weights[i] = self.weights[i] + weight_delta;
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.pre_indicies);
        self.allocator.free(self.post_indicies);
        self.allocator.free(self.eligibility_traces);
        self.allocator.free(self.last_spike_times);
    }
};

pub fn calculate_stdp_curve(delta: f32) f32 {
    if (delta > 0) {
        return aplus * @exp(delta / tau_plus);
    }

    if (delta < 0) {
        return aplus * @exp(-delta / tau_minus);
    }
}
