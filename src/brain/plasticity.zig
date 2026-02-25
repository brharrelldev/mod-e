const std = @import("std");

const max_neuron_count: usize = 2048;

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
pub const Plasticity = struct {
    weights: []f32,
    eligibility_traces: []f32,
    pre_indicies: []u16, //column (csc)
    post_pointers: []u16, // rows (cSR)
    last_spike_times: []u64,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const weights = try allocator.alloc(f32, max_neuron_count);
        const eligibility_traces = try allocator.alloc(f32, max_neuron_count);
        const pre_indicies = try allocator.alloc(u16, max_neuron_count);
        const last_spike_times = try allocator.alloc(u64, max_neuron_count);

        return Self{
            .weights = weights,
            .eligibility_traces = eligibility_traces,
            .pre_indicies = pre_indicies,
            .last_spike_times = last_spike_times,
        };
    }
};
