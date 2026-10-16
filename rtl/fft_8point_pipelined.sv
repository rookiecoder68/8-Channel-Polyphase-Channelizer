`timescale 1ns / 1ps

module fft_8point_pipelined (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      fir_valid,
    input  logic signed [7:0][15:0]   v_r,        // 8 real inputs from FIR

    output logic                      m_valid,
    output logic signed [15:0]        m_data_re,  // Serialized complex outputs
    output logic signed [15:0]        m_data_im
);

    // Twiddle Constants & Helpers
    // 1/sqrt(2) in Q1.15 format
    localparam signed [31:0] C = 32'sd23170;

    // Yosys-safe Sign Extension
    function automatic logic signed [31:0] sign_extend_16;
        input logic [15:0] val;
        begin
            sign_extend_16 = {{16{val[15]}}, val};
        end
    endfunction

    // Yosys-safe Scalar multiplication with standard rounding
    function automatic logic signed [31:0] mult_C;
        input logic signed [31:0] val;
        logic signed [63:0] prod;
        logic signed [63:0] shifted;
        begin
            prod = val * C;
            prod = prod + 64'sd16384; 
            shifted = prod >>> 15;
            mult_C = shifted[31:0]; // Replaced 32'(...) cast with part-select
        end
    endfunction

    // Yosys-safe Exact round-half-to-even logic
    function automatic logic signed [31:0] round_div8;
        input logic signed [31:0] val;
        logic signed [31:0] shifted;
        begin
            shifted = val >>> 3;
            if (val[2:0] > 3'd4) 
                shifted = shifted + 1'b1;
            else if (val[2:0] == 3'd4) 
                shifted = shifted + shifted[0]; 
            round_div8 = shifted;
        end
    endfunction

    // Stage 1: Distance 4 Butterflies
    logic signed [31:0] a0, b0, a1, b1_re, b1_im, a2, b2_im, a3, b3_re, b3_im;
    logic stg1_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg1_valid <= 1'b0;
            a0 <= '0; b0 <= '0; a1 <= '0; b1_re <= '0; b1_im <= '0;
            a2 <= '0; b2_im <= '0; a3 <= '0; b3_re <= '0; b3_im <= '0;
        end else begin
            stg1_valid <= fir_valid;
            if (fir_valid) begin
                a0 <= sign_extend_16(v_r[0]) + sign_extend_16(v_r[4]);
                b0 <= sign_extend_16(v_r[0]) - sign_extend_16(v_r[4]);

                a1 <= sign_extend_16(v_r[1]) + sign_extend_16(v_r[5]);
                b1_re <=  mult_C(sign_extend_16(v_r[1]) - sign_extend_16(v_r[5]));
                b1_im <= -mult_C(sign_extend_16(v_r[1]) - sign_extend_16(v_r[5]));

                a2 <= sign_extend_16(v_r[2]) + sign_extend_16(v_r[6]);
                b2_im <= -(sign_extend_16(v_r[2]) - sign_extend_16(v_r[6]));

                a3 <= sign_extend_16(v_r[3]) + sign_extend_16(v_r[7]);
                b3_re <= -mult_C(sign_extend_16(v_r[3]) - sign_extend_16(v_r[7]));
                b3_im <= -mult_C(sign_extend_16(v_r[3]) - sign_extend_16(v_r[7]));
            end
        end
    end

    // Stage 2: Distance 2 Butterflies
    logic signed [31:0] c0, d0, c1, d1_im;
    logic signed [31:0] c2_re, c2_im, d2_re, d2_im;
    logic signed [31:0] c3_re, c3_im, d3_re, d3_im;
    logic stg2_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg2_valid <= 1'b0;
            c0 <= '0; d0 <= '0; c1 <= '0; d1_im <= '0;
            c2_re <= '0; c2_im <= '0; d2_re <= '0; d2_im <= '0;
            c3_re <= '0; c3_im <= '0; d3_re <= '0; d3_im <= '0;
        end else begin
            stg2_valid <= stg1_valid;
            if (stg1_valid) begin
                c0 <= a0 + a2;
                d0 <= a0 - a2;

                c1 <= a1 + a3;
                d1_im <= -(a1 - a3);

                c2_re <= b0;
                c2_im <= b2_im;

                d2_re <= b0;
                d2_im <= -b2_im;

                c3_re <= b1_re + b3_re;
                c3_im <= b1_im + b3_im;

                d3_re <= b1_im - b3_im;
                d3_im <= -(b1_re - b3_re);
            end
        end
    end

    // Stage 3: Distance 1 & Output Buffer
    logic signed [31:0] Y_re [0:7];
    logic signed [31:0] Y_im [0:7];
    logic stg3_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg3_valid <= 1'b0;
            for(int i=0; i<8; i++) begin
                Y_re[i] <= '0;
                Y_im[i] <= '0;
            end
        end else begin
            stg3_valid <= stg2_valid;
            if (stg2_valid) begin
                Y_re[0] <= c0 + c1;       Y_im[0] <= '0;
                Y_re[4] <= c0 - c1;       Y_im[4] <= '0;

                Y_re[2] <= d0;            Y_im[2] <= d1_im;
                Y_re[6] <= d0;            Y_im[6] <= -d1_im;

                Y_re[1] <= c2_re + c3_re; Y_im[1] <= c2_im + c3_im;
                Y_re[5] <= c2_re - c3_re; Y_im[5] <= c2_im - c3_im;

                Y_re[3] <= d2_re + d3_re; Y_im[3] <= d2_im + d3_im;
                Y_re[7] <= d2_re - d3_re; Y_im[7] <= d2_im - d3_im;
            end
        end
    end

    // Serializer & Quantization 
    logic [2:0] tx_count;
    logic       tx_active;
    logic signed [31:0] tx_re [0:7];
    logic signed [31:0] tx_im [0:7];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
            tx_active <= 1'b0;
            tx_count <= '0;
            m_data_re <= '0;
            m_data_im <= '0;
            for (int i = 0; i < 8; i++) begin
                tx_re[i] <= '0;
                tx_im[i] <= '0;
            end
        end else begin
            // Serialization State Machine
            if (stg3_valid) begin
                for (int i = 0; i < 8; i++) begin
                    tx_re[i] <= Y_re[i];
                    tx_im[i] <= Y_im[i];
                end
                tx_active <= 1'b1;
                tx_count <= 3'd0;
            end else if (tx_active) begin
                if (tx_count == 3'd7) begin
                    tx_active <= 1'b0;
                end else begin
                    tx_count <= tx_count + 1'b1;
                end
            end
            
            m_valid <= tx_active;
            
            if (tx_active) begin
                logic signed [31:0] rnd_re, rnd_im;
                
                rnd_re = round_div8(tx_re[tx_count]);
                rnd_im = round_div8(tx_im[tx_count]);

                // Saturate to 16-bit bounds and map using [15:0] instead of 16'(...)
                if (rnd_re > 32'sd32767) m_data_re <= 16'sd32767;
                else if (rnd_re < -32'sd32768) m_data_re <= -16'sd32768;
                else m_data_re <= rnd_re[15:0];

                if (rnd_im > 32'sd32767) m_data_im <= 16'sd32767;
                else if (rnd_im < -32'sd32768) m_data_im <= -16'sd32768;
                else m_data_im <= rnd_im[15:0];
            end
        end
    end

endmodule