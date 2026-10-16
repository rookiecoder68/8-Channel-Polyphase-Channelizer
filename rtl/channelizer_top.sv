`timescale 1ns / 1ps

module channelizer_top (
    input  logic               clk,
    input  logic               rst_n,
    
    // Streaming Input Interface
    input  logic               s_valid,
    input  logic signed [15:0] s_data,       // Real, 16-bit signed integer samples[cite: 2]
    
    // Streaming Output Interface
    output logic               m_valid,
    output logic signed [15:0] m_data_re,    // 16-bit signed complex values delivered serially[cite: 2]
    output logic signed [15:0] m_data_im
);

    // Interconnect Signals
     
    logic                      frame_valid;
    logic signed [7:0][15:0]   frame_data;
    
    logic                      fir_valid;
    logic signed [7:0][15:0]   v_r;

    // Sub-module Instantiations
     
    // 1. Input Commutator: Converts serial stream to 8-sample parallel frames
    input_buffer u_input_buffer (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_valid     (s_valid),
        .s_data      (s_data),
        .frame_valid (frame_valid),
        .frame_data  (frame_data)
    );

    // 2. Folded Polyphase FIR: Computes branch outputs v_r using exact accumulation[cite: 3]
    folded_fir u_folded_fir (
        .clk         (clk),
        .rst_n       (rst_n),
        .frame_valid (frame_valid),
        .frame_data  (frame_data),
        .fir_valid   (fir_valid),
        .v_r         (v_r)
    );

    // 3. 8-Point SDF FFT: Processes branch outputs into serial frequency bins[cite: 2]
    fft_8point_pipelined u_fft (
        .clk         (clk),
        .rst_n       (rst_n),
        .fir_valid   (fir_valid),
        .v_r         (v_r),
        .m_valid     (m_valid),
        .m_data_re   (m_data_re),
        .m_data_im   (m_data_im)
    );

endmodule