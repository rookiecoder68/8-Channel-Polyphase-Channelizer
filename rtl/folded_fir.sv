`timescale 1ns / 1ps

module folded_fir (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      frame_valid,
    input  logic signed [7:0][15:0]   frame_data, // 8-sample block from input_buffer

    output logic                      fir_valid,  // High for 1 cycle when v_r array is ready
    output logic signed [7:0][15:0]   v_r         // 8 computed branch outputs
);

    // 1. Memory and Buffers
    logic signed [15:0] coeff [0:31];
    logic signed [15:0] hist [0:31];
    logic [14:0] acc_frac;
    logic        acc_rnd_bit;
    

    // Initialize coefficients via a hex file for Yosys synthesis
    initial begin
        $readmemh("../synth/coeffs.hex", coeff); 
    end

    // 2. FSM and Control Signals
    typedef enum logic {IDLE, CALC} state_t;
    state_t state;
    
    logic [2:0] r; // Branch index counter (0 to 7)

    // 3. Datapath: MAC & Quantization Signals
    logic signed [31:0] prod_0, prod_1, prod_2, prod_3;
    logic signed [39:0] acc;
    logic signed [39:0] acc_shifted;
    logic               round_up;
    logic signed [39:0] acc_rounded;
    logic signed [15:0] saturated_out;

    // MAC Multipliers (Combinational)
    always_comb begin
        prod_0 = coeff[r]      * hist[r];
        prod_1 = coeff[r + 8]  * hist[r + 8];
        prod_2 = coeff[r + 16] * hist[r + 16];
        prod_3 = coeff[r + 24] * hist[r + 24];
        
        // Exact integer accumulation (Reduced from 64-bit to 40-bit)
        acc = 40'(prod_0) + 40'(prod_1) + 40'(prod_2) + 40'(prod_3);
    end

    // Extracted signals to bypass iverilog part-select limitation
    assign acc_frac = acc[14:0];
    assign acc_rnd_bit = acc[15];

    // Round-Half-to-Even and Saturation Logic
    always_comb begin
        // Arithmetic shift applies the 2^-15 scaling while preserving sign
        acc_shifted = acc >>> 15;
        
        // 15'h4000 represents exactly 0.5 in the discarded lower 15 bits
        if (acc_frac > 15'h4000) begin
            round_up = 1'b1;
        end else if (acc_frac == 15'h4000) begin
            // If exactly halfway, round to nearest even by adding 1 only if the LSB is odd
            round_up = acc_rnd_bit; 
        end else begin
            round_up = 1'b0;
        end
        
        acc_rounded = acc_shifted + 40'(round_up);
        
        // Saturate to 16-bit signed range
        if (acc_rounded > 40'sd32767)
            saturated_out = 16'sd32767;
        else if (acc_rounded < -40'sd32768)
            saturated_out = -16'sd32768;
        else
            saturated_out = 16'(acc_rounded);
    end

    // 4. Sequential Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            r <= 3'd0;
            fir_valid <= 1'b0;
            v_r <= '0;
            for (int i = 0; i < 32; i++) begin
                hist[i] <= 16'd0;
            end
        end else begin
            fir_valid <= 1'b0; // Default to a 1-cycle pulse

            case (state)
                IDLE: begin
                    if (frame_valid) begin
                        // Shift history buffer by 8 positions
                        for (int i = 31; i >= 8; i--) begin
                            hist[i] <= hist[i-8];
                        end
                        // Load newest 8-sample frame. 
                        // frame_data[7] is the newest sample x[8m+7], mapping to hist[0]
                        hist[0] <= frame_data[7];
                        hist[1] <= frame_data[6];
                        hist[2] <= frame_data[5];
                        hist[3] <= frame_data[4];
                        hist[4] <= frame_data[3];
                        hist[5] <= frame_data[2];
                        hist[6] <= frame_data[1];
                        hist[7] <= frame_data[0];
                        
                        state <= CALC;
                        r <= 3'd0;
                    end
                end

                CALC: begin
                    // Store the computed and saturated branch output[cite: 2, 3]
                    v_r[r] <= saturated_out;
                    
                    if (r == 3'd7) begin
                        fir_valid <= 1'b1;
                        if (frame_valid) begin
                            // The next frame arrives on the same cycle as
                            // the final branch, so begin its calculation
                            // without inserting a bubble.
                            for (int i = 31; i >= 8; i--) begin
                                hist[i] <= hist[i-8];
                            end
                            hist[0] <= frame_data[7];
                            hist[1] <= frame_data[6];
                            hist[2] <= frame_data[5];
                            hist[3] <= frame_data[4];
                            hist[4] <= frame_data[3];
                            hist[5] <= frame_data[2];
                            hist[6] <= frame_data[1];
                            hist[7] <= frame_data[0];
                            state <= CALC;
                            r <= 3'd0;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        r <= r + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule