`timescale 1ns / 1ps

module tb_channelizer_top;

    // ==========================================
    // 1. Clock and Reset Generation
    // ==========================================
    logic clk;
    logic rst_n;

    // 10.0 ns clock period -> 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ==========================================
    // 2. DUT Interfaces
    // ==========================================
    logic               s_valid;
    logic signed [15:0] s_data;
    
    logic               m_valid;
    logic signed [15:0] m_data_re;
    logic signed [15:0] m_data_im;

    // ==========================================
    // 3. Memory & Tracking Variables
    // ==========================================
    // 60 frames * 8 samples/bins = 480 total words
    localparam NUM_FRAMES = 60;
    localparam NUM_SAMPLES = NUM_FRAMES * 8;
    
    logic signed [15:0] stim_mem [0:NUM_SAMPLES-1];
    logic        [31:0] exp_mem  [0:NUM_SAMPLES-1]; // Holds 32-bit hex (16-bit real_16-bit imag)
    
    integer input_idx = 0;
    integer output_idx = 0;
    integer frame_count = 0;
    integer mismatch_count = 0;
    
    integer max_error_re = 0;
    integer max_error_im = 0;
    integer current_error_re, current_error_im;
    
    // Latency tracking
    integer start_time = 0;
    integer latency_cycles = 0;
    logic   latency_measured = 0;

    // ==========================================
    // 4. DUT Instantiation
    // ==========================================
    channelizer_top u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_valid    (s_valid),
        .s_data     (s_data),
        .m_valid    (m_valid),
        .m_data_re  (m_data_re),
        .m_data_im  (m_data_im)
    );

    // ==========================================
    // 5. Test Stimulus Driver
    // ==========================================
    initial begin
        // Load Python reference files
        $readmemh("stimulus.hex", stim_mem);
        
        // Verilog ignores the '_' separator, seamlessly reading "03e8_fc18" into a 32-bit word
        $readmemh("expected_output.hex", exp_mem);
        
        $display("===============================================================");
        $display("   STARTING CHANNELIZER TESTBENCH (V1, V2, V3 Stimulus)");
        $display("===============================================================");
        
        // Assert Reset
        rst_n = 0;
        s_valid = 0;
        s_data = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        
        // Feed Data
        while (input_idx < NUM_SAMPLES) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= stim_mem[input_idx];
            
            // Mark the timestamp of the newest input sample x[8m+7] to calculate latency[cite: 2, 4]
            if ((input_idx % 8) == 7 && !latency_measured) begin
                start_time = $time;
            end
            
            input_idx++;
        end
        
        @(posedge clk);
        s_valid <= 1'b0; // End of transmission
    end

    // ==========================================
    // 6. Verification Checker & Dashboard Logger
    // ==========================================
    logic signed [15:0] expected_re;
    logic signed [15:0] expected_im;
    
    always @(posedge clk) begin
        if (m_valid) begin
            
            frame_count = output_idx / 8;
            
            // Ensure we measure latency ONLY on valid initialized data (Frame 3)
            if (!latency_measured && start_time > 0 && frame_count == 3) begin
                latency_cycles = ($time - start_time) / 10;
                latency_measured = 1'b1;
                $display(">>> LATENCY MEASURED: %0d clock cycles <<<", latency_cycles);
            end
            
            // Unpack the expected outputs
            expected_re = exp_mem[output_idx][31:16];
            expected_im = exp_mem[output_idx][15:0];
            
            // Calculate absolute LSB errors
            current_error_re = (m_data_re > expected_re) ? (m_data_re - expected_re) : (expected_re - m_data_re);
            current_error_im = (m_data_im > expected_im) ? (m_data_im - expected_im) : (expected_im - m_data_im);
            
            // Track worst-case error for the results dashboard
            if (current_error_re > max_error_re) max_error_re = current_error_re;
            if (current_error_im > max_error_im) max_error_im = current_error_im;
            
            // Ignore the first 3 frames after reset for value checking
            if (frame_count >= 3) begin
                if (current_error_re > 2 || current_error_im > 2) begin
                    $display("[FAIL] Frame %0d, Bin %0d | Exp: (%0d, %0d) | Got: (%0d, %0d) | Err: (%0d, %0d)", 
                        frame_count, (output_idx % 8), expected_re, expected_im, m_data_re, m_data_im, current_error_re, current_error_im);
                    mismatch_count++;
                end
            end
            
            output_idx++;
            
            // End of simulation check
            if (output_idx == NUM_SAMPLES) begin
                $display("\n===============================================================");
                $display("                 RESULTS DASHBOARD                            ");
                $display("===============================================================");
                $display("Total Frames Processed : %0d", NUM_FRAMES);
                $display("Frames Skipped (Init)  : 3");
                $display("Measured Latency       : %0d cycles", latency_cycles);
                $display("Worst-Case Real Error  : %0d LSB", max_error_re);
                $display("Worst-Case Imag Error  : %0d LSB", max_error_im);
                $display("Total Failed Bins      : %0d", mismatch_count);
                
                if (mismatch_count == 0 && max_error_re <= 2 && max_error_im <= 2) begin
                    $display("===============================================================");
                    $display("   FINAL VERDICT: PASS (Meets +/- 2 LSB tolerance)");
                    $display("===============================================================");
                end else begin
                    $display("===============================================================");
                    $display("   FINAL VERDICT: FAIL (Exceeded +/- 2 LSB tolerance)");
                    $display("===============================================================");
                end
                $finish;
            end
        end
    end

endmodule