`timescale 1ns / 1ps

module SystolicArray #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ARRAY_SIZE = 8
) (
    input logic clk,
    input logic rst_n,
    
    input logic signed [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] vec_in_a,
    input logic signed [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] vec_in_b,
    input logic valid_in,
    input logic acc_clear,
    input logic [$clog2(ACC_WIDTH)-1:0] shift_amount,

    output logic signed [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][DATA_WIDTH-1:0] out_row_aligned,
    output logic [ARRAY_SIZE-1:0] valid_row_aligned,
);
    // --- INPUT SKEW BUFFERS ---
    logic signed [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] a_skewed;
    logic signed [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] b_skewed;
    logic [ARRAY_SIZE-1:0] valid_in_skewed;
    logic [ARRAY_SIZE-1:0] acc_clear_skewed;

    genvar i, j;
    generate
        for(i = 0; i < ARRAY_SIZE; i++) begin: skew
            if(i == 0) begin
                assign a_skewed[i] = vec_in_a[i];
                assign b_skewed[i] = vec_in_b[i];
                assign valid_in_skewed[i] = valid_in;
                assign acc_clear_skewed[i] = acc_clear;
            end
            else begin
                // Tạo shift register độ sâu i
                logic signed [i:1][DATA_WIDTH-1:0] a_delay;
                logic signed [i:1][DATA_WIDTH-1:0] b_delay;
                logic [i:1] v_delay;
                logic [i:1] c_delay;

                always_ff @(posedge clk) begin
                    if(!rst_n) begin
                        a_delay <= '0;
                        b_delay <= '0;
                        v_delay <= '0;
                        c_delay <= '0;
                    end
                    else begin
                        a_delay[1] <= vec_in_a[i];
                        b_delay[1] <= vec_in_b[i];
                        v_delay[1] <= valid_in;
                        c_delay[1] <= acc_clear;

                        for(int k = 2; k <= i; k++) begin
                            a_delay[k] <= a_delay[k-1];
                            b_delay[k] <= b_delay[k-1];
                            v_delay[k] <= v_delay[k-1];
                            c_delay[k] <= c_delay[k-1];
                        end
                    end
                end

                assign a_skewed[i] = a_delay[i];
                assign b_skewed[i] = b_delay[i];
                assign valid_in_skewed[i] = v_delay[i];
                assign acc_clear_skewed[i] = c_delay[i];
            end
        end
    endgenerate

    // --- PE Matrix ---
    logic signed [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][DATA_WIDTH-1:0] pe_out_matrix;
    logic [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0] pe_valid_matrix;

    logic signed [ARRAY_SIZE-1:0][ARRAY_SIZE:0][DATA_WIDTH-1:0] a_wire;
    logic signed [ARRAY_SIZE:0][ARRAY_SIZE-1:0][DATA_WIDTH-1:0] b_wire;
    logic [ARRAY_SIZE-1:0][ARRAY_SIZE:0] v_wire;
    logic [ARRAY_SIZE-1:0][ARRAY_SIZE:0] c_wire;

    generate
        for(i = 0; i < ARRAY_SIZE; i++) begin
            assign a_wire[i][0] = a_skewed[i];
            assign b_wire[0][i] = b_skewed[i];
            assign v_wire[i][0] = valid_in_skewed[i];
            assign c_wire[i][0] = acc_clear_skewed[i];
        end
    endgenerate

    generate
        for(i = 0; i < ARRAY_SIZE; i++) begin: row
            for(j = 0; j < ARRAY_SIZE; j++) begin: col
                PE #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe (
                    .clk(clk), .rst_n(rst_n),
                    .valid_in(v_wire[i][j]), .acc_clear(c_wire[i][j]),
                    .shift_amount(shift_amount),
                    .in_a(a_wire[i][j]), .in_b(b_wire[i][j]),
                    .out_a(a_wire[i][j+1]), .out_b(b_wire[i+1][j]),
                    .out_valid_ctrl(v_wire[i][j+1]), .out_clear_ctrl(c_wire[i][j+1]),
                    .valid_out(pe_valid_matrix[i][j]), .pe_out(pe_out_matrix[i][j])
                );
            end
        end
    endgenerate

    // --- OUTPUT ALIGNMENT ---
    // Tín hiệu valid_out của cột j bị trễ j chu kỳ so với cột 0
    // Để ghi vào SRAM nguyên 1 hàng, cần làm trễ cột j thêm (ARRAY_SIZE - 1 - j) chu kỳ
    generate
        for(i = 0; i < ARRAY_SIZE; i++) begin: out_row
            for(j = 0; j < ARRAY_SIZE; j++) begin: out_col
                localparam DELAY_CYCLES = ARRAY_SIZE - 1 - j;

                if(DELAY_CYCLES == 0) begin
                    assign out_row_aligned[i][j] = pe_out_matrix[i][j];
                    assign valid_row_aligned[i] = pe_valid_matrix[i][j];
                end
                else begin
                    logic signed [DELAY_CYCLES:1][DATA_WIDTH-1:0] out_delay;

                    always_ff @(posedge clk) begin
                        out_delay[1] <= pe_out_matrix[i][j];
                        
                        for(int k = 2; k <= DELAY_CYCLES; k++) begin
                            out_delay[k] <= out_delay[k-1];
                        end
                    end

                    assign out_row_aligned[i][j] = out_delay[DELAY_CYCLES];
                end
            end
        end
    endgenerate
    
endmodule