`timescale 1ns / 1ps

module input_buffer (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               s_valid,      
    input  logic signed [15:0] s_data,       

    output logic               frame_valid,  
    output logic signed [7:0][15:0] frame_data 
);

    logic [2:0] count;
    logic signed [15:0] shift_reg [0:7];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 3'd0;
            frame_valid <= 1'b0;
            frame_data <= '0;
            for (int i = 0; i < 8; i++) begin
                shift_reg[i] <= 16'd0;
            end
        end else begin
            frame_valid <= 1'b0; 

            if (s_valid) begin
                for (int i = 0; i < 7; i++) begin
                    shift_reg[i] <= shift_reg[i+1];
                end
                shift_reg[7] <= s_data;

                if (count == 3'd7) begin
                    count <= 3'd0;
                    frame_valid <= 1'b1;
                    
                    // CORRECTED INDEXING: Matches the exact 8-sample pipeline depth
                    frame_data[7] <= s_data;       // Newest sample (0-cycle latency)
                    frame_data[6] <= shift_reg[7]; 
                    frame_data[5] <= shift_reg[6];
                    frame_data[4] <= shift_reg[5];
                    frame_data[3] <= shift_reg[4];
                    frame_data[2] <= shift_reg[3];
                    frame_data[1] <= shift_reg[2];
                    frame_data[0] <= shift_reg[1]; // Oldest sample
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end

endmodule