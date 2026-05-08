`timescale 1ns/1ps

module Controller #(
    parameter ACC_WIDTH = 32,
    parameter NUM_HEADS = 2
) (
    input logic clk,
    input logic rst_n,

    // Giao tiếp với Top Module
    input logic system_start,
    output logic system_done,

    // --- MẢNG 10 THANH GHI SHIFT & sfm_q_frac ---
    // [0]:Q, [1]:K, [2]:V, [3]:Score_H0, [4]:Score_H1, 
    // [5]:Attn_H0, [6]:Attn_H1, [7]:Proj_O, [8]:FFN1, [9]:FFN2
    input logic [4:0] cfg_shifts [0:9],
    input logic [3:0] head_q_frac [NUM_HEADS-1:0],

    input logic stage_done, // Nhận tín hiệu từ Datapath mỗi khi done 1 stage

    // Điều khiển Datapath
    output logic start_matmul,
    output logic transpose_mode,
    output logic [$clog2(ACC_WIDTH)-1:0] shift_amount,

    // MHA controll
    output logic multi_head,
    output logic [$clog2(NUM_HEADS)-1:0] head_idx,
    output logic start_softmax,
    output logic [3:0] sfm_q_frac,
    output logic start_transpose,
    output logic is_calc_z,

    output logic [2:0] sel_in_a, sel_in_b,
    output logic we_sram_x, we_sram_0, we_sram_1, we_sram_2, we_sram_3, we_sram_4
);
    
    typedef enum logic [4:0] {
        IDLE,
        LAYERNORM, WAIT_LN,
        CALC_Q, WAIT_Q,
        CALC_K, WAIT_K,
        CALC_V, WAIT_V,
        CALC_E, WAIT_E,
        SOFTMAX, WAIT_SOFTMAX,
        TRANSPOSE, WAIT_TRANSPOSE,
        CALC_Z, WAIT_Z,
        CALC_MHA_OUT, WAIT_MHA_OUT,
        DONE
    } state_t;

    state_t state, next_state;
    logic [$clog2(NUM_HEADS)-1:0] next_head_counter;
    // ==================================================
    // CHANGE STATE
    // ==================================================
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            state <= IDLE;
            head_idx <= 0; 
        end
        else begin
            state <= next_state;
            head_idx <= next_head_counter; 
        end
    end

    // ==================================================
    // NEXT STATE LOGIC
    // ==================================================
    always_comb begin
        next_state = state;
        next_head_counter = head_idx;
        case(state)
            IDLE: if(system_start) next_state = LAYERNORM;
            
            LAYERNORM: next_state = CALC_Q;
            WAIT_LN: next_state = CALC_Q;

            CALC_Q: next_state = WAIT_Q;
            WAIT_Q: if(stage_done) next_state = CALC_K;

            CALC_K: next_state = WAIT_K;
            WAIT_K: if(stage_done) next_state = CALC_V;

            CALC_V: next_state = WAIT_V;
            WAIT_V: if(stage_done) next_state = CALC_E;

            CALC_E: next_state = WAIT_E;
            WAIT_E: if(stage_done) next_state = SOFTMAX;

            SOFTMAX: next_state = WAIT_SOFTMAX;
            WAIT_SOFTMAX: if(stage_done) next_state = TRANSPOSE;

            TRANSPOSE: next_state = WAIT_TRANSPOSE;
            WAIT_TRANSPOSE: if(stage_done) next_state = CALC_Z;

            CALC_Z: next_state = WAIT_Z;
            WAIT_Z: begin 
                if(stage_done) begin
                    if(head_idx == NUM_HEADS - 1) begin
                        next_state = CALC_MHA_OUT;
                        next_head_counter = 0;
                    end
                    else begin
                        next_state = CALC_E;
                        next_head_counter = head_idx + 1;
                    end
                end 
            end

            CALC_MHA_OUT: next_state = WAIT_MHA_OUT;
            WAIT_MHA_OUT: if(stage_done) next_state = DONE;
 
            DONE: next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    // ==================================================
    // OUTPUT LOGIC
    // ==================================================
    always_comb begin
        start_matmul = 0;
        transpose_mode = 0;
        shift_amount = 8;
        multi_head = 0;
        system_done = 0;

        sel_in_a = 3'd0; sel_in_b = 3'd0;
        we_sram_x = 0; we_sram_0 = 0; we_sram_1 = 0; we_sram_2 = 0; we_sram_3 = 0; we_sram_4 = 0;
        start_softmax = 0; start_transpose = 0; sfm_q_frac = 0; is_calc_z = 0;

        case(state)
            CALC_Q, WAIT_Q: begin
                if (state == CALC_Q) start_matmul = 1;
                transpose_mode = 1;
                sel_in_a = 3'd0;
                sel_in_b = 3'd1;
                we_sram_3 = 1;
                shift_amount = cfg_shifts[0];
            end

            CALC_K, WAIT_K: begin
                if(state == CALC_K) start_matmul = 1;
                transpose_mode = 1;
                sel_in_a = 3'd0;
                sel_in_b = 3'd2;
                we_sram_4 = 1;
                shift_amount = cfg_shifts[1];
            end

            CALC_V, WAIT_V: begin
                if(state == CALC_V) start_matmul = 1;
                transpose_mode = 0;
                sel_in_a = 3'd0;
                sel_in_b = 3'd3;
                we_sram_0 = 1;
                shift_amount = cfg_shifts[2];
            end

            CALC_E, WAIT_E: begin
                if(state == CALC_E) start_matmul = 1;
                multi_head = 1;
                sel_in_a = 3'd4;
                sel_in_b = 3'd5;
                we_sram_1 = 1;
                shift_amount = cfg_shifts[3 + head_idx];
            end

            SOFTMAX, WAIT_SOFTMAX: begin
                if(state == SOFTMAX) start_softmax = 1;
                sfm_q_frac = head_q_frac[head_idx];
            end

            TRANSPOSE, WAIT_TRANSPOSE: begin
                if(state == TRANSPOSE) start_transpose = 1;
            end

            CALC_Z, WAIT_Z: begin
                if(state == CALC_Z) start_matmul = 1;
                is_calc_z = 1;
                transpose_mode = 1;
                multi_head = 1;
                sel_in_a = 3'd2;
                sel_in_b = 3'd1;
                we_sram_3 = 1;
                shift_amount = cfg_shifts[5 + head_idx];
            end

            CALC_MHA_OUT, WAIT_MHA_OUT: begin
                if(state == CALC_MHA_OUT) start_matmul = 1;
                transpose_mode = 0;
                sel_in_a = 3'd4;
                sel_in_b = 3'd5;
                we_sram_0 = 1;
                shift_amount = cfg_shifts[7];
            end

            DONE: system_done = 1;
        endcase
    end
    
endmodule