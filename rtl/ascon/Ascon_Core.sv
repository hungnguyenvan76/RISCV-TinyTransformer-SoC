`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Hung Nguyen
// Create Date: 04/28/2026 09:34:00 AM
// Module Name: Ascon_Core
// Project Name: Ascon-AEAD128
// Description: Connecting FSM, Datapath and Permutation
//////////////////////////////////////////////////////////////////////////////////

//thiếu padding cho message cuối cùng khi độ dài không phải bội của RATE_CHUNKS*8 bytes

module Ascon_Core import ascon_pkg::*; (
    input  logic         clk,
    input  logic         reset_n,

    input  logic         mess_valid,
    output logic         mess_pull,
    input  logic [63:0]  message,
    input  logic         mess_last,

    output logic         cipher_push,
    input  logic         cipher_ready,
    output logic [63:0]  cipher,
    output logic         cipher_last,
    
    input  logic         start,
    input  logic [127:0] key,
    input  logic [127:0] nonce,
    input  logic [1:0]   mode,
    input  logic         skip_asso,
    input  logic [127:0] in_tag,
    output logic [127:0] out_tag,
    output logic         success_tag,
    output logic         done
);
    // RATE_CHUNKS = 2 - Ascon-AEAD128 
    localparam int RC_MAX = 1; 

    logic [0:4][63:0] S;
    logic [0:4][63:0] perm_in, perm_out;
    logic perm_start, perm_done;
    logic [3:0] perm_rounds;
    logic cycle_cnt; 
    logic cycle_done;
    logic [2:0] state;
    logic pad_phase;
    logic is_full_block;
    
    assign cycle_done = (cycle_cnt == RC_MAX);

    Ascon_FSM u_fsm (
        .clk        (clk), 
        .reset_n    (reset_n), 
        .start      (start),
        .mode       (mode), 
        .skip_asso  (skip_asso),
        .mess_valid (mess_valid), 
        .mess_last  (mess_last),
        .cycle_done (cycle_done), 
        .perm_done  (perm_done),
        .perm_start (perm_start), 
        .perm_rounds(perm_rounds),
        .mess_pull  (mess_pull), 
        .cipher_push(cipher_push),
        .cipher_ready(cipher_ready),
        .done       (done), 
        .state_out  (state),
        .pad_phase  (pad_phase),
        .is_full_block(is_full_block)
    );

    Permutation u_perm (
        .clk        (clk), 
        .rst_n      (reset_n), 
        .start      (perm_start),
        .num_rounds (perm_rounds), 
        .x_in       (perm_in),
        .x_out      (perm_out), 
        .done       (perm_done)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            S <= '0;
            cycle_cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    cycle_cnt <= 0;
                    if (start) begin
                        // IV Ascon-AEAD128 NIST SP 800-232 
                        S[0] <= ASCON_IV; 
                        S[1] <= key[127:64];  
                        S[2] <= key[63:0];
                        S[3] <= nonce[127:64]; 
                        S[4] <= nonce[63:0];
                    end
                end

                INIT: begin
                    if (perm_done) begin
                        // S = S ^ (0^192 || K)
                        S <= perm_out; 
                        S[3] <= perm_out[3] ^ key[127:64]; 
                        S[4] <= perm_out[4] ^ key[63:0];
                    end
                end

                ASSO_DATA: begin
                    if (mess_valid && mess_pull) begin
                        if (cycle_cnt == 0) begin
                            S[0] <= S[0] ^ message;
                            if (mess_last) S[1] <= PAD(S[1]);
                        end
                        else 
                            S[1] <= S[1] ^ message;
                        
                        if (cycle_done || mess_last ) 
                            cycle_cnt <= 0;
                        else 
                            cycle_cnt <= cycle_cnt + 1;
                    end
      
                    if (perm_done) begin
                        S <= perm_out;
                        if ((is_full_block && pad_phase) || (!is_full_block)) 
                            S[4] <= perm_out[4] ^ 64'h8000000000000000; // Domain Separation
                    end
                end


                MESSAGE: begin
                    if (mess_valid && mess_pull) begin
                        if (mode == 2'b01) begin 
                            // MODE: DECRYPT 
                            if (cycle_cnt == 0) begin
                                S[0] <= message;
                                if (mess_last) S[1] <= PAD(S[1]);
                            end
                            else 
                                S[1] <= message;
                        end 
                        else begin 
                            // MODE: ENCRYPT 
                            if (cycle_cnt == 0) begin
                                S[0] <= S[0] ^ message;
                                if (mess_last) S[1] <= PAD(S[1]);
                            end
                            else  
                                S[1] <= S[1] ^ message;
                        end
                        
                        if (cycle_done || mess_last) 
                            cycle_cnt <= 0;
                        else            
                            cycle_cnt <= cycle_cnt + 1;
                    end
      
                    if (perm_done) begin
                        S <= perm_out;
                    end
                end

                TAG: begin
                    if (perm_done) S <= perm_out;
                end
            endcase
        end
    end

    // Cipher output XOR
    assign cipher = (cycle_cnt == 0) ? (S[0] ^ message) : (S[1] ^ message);
    assign cipher_last = mess_last;

    always_comb begin
        perm_in = S; 

        if (state == ASSO_DATA) begin
            if (mess_valid && mess_pull) begin
                if (cycle_cnt == 0) begin
                    perm_in[0] = S[0] ^ message;
                    if (mess_last) perm_in[1] = PAD(S[1]);
                end
                else                
                    perm_in[1] = S[1] ^ message;
            end
            else if (pad_phase) begin 
                // run permutation for block padding
                if (is_full_block) perm_in[0] = PAD(S[0]);
            end
        end

        else if (state == MESSAGE && mess_valid && mess_pull) begin
            if (mode == 2'b01) begin 
                // MODE: DECRYPT 
                if (cycle_cnt == 0) begin
                    perm_in[0] = message;
                    if (mess_last) perm_in[1] = PAD(S[1]);
                end
                else                
                    perm_in[1] = message;
            end 
            else begin 
                // MODE: ENCRYPT 
                if (cycle_cnt == 0) begin
                    perm_in[0] = S[0] ^ message;
                    if (mess_last) perm_in[1] = PAD(S[1]);
                end
                else                
                    perm_in[1] = S[1] ^ message;
            end
            
        end
        else if (state == TAG && !perm_done) begin
            if (is_full_block) perm_in[0] = PAD(S[0]);
            perm_in[2] = S[2] ^ key[127:64];
            perm_in[3] = S[3] ^ key[63:0];
        end
    end
    
    // Tag S[3] and S[4] XOR Key
    assign out_tag = {perm_out[3] ^ key[127:64], perm_out[4] ^ key[63:0]};
    assign success_tag = (mode == 2'b01) ? (out_tag == in_tag) : 1'b1;

endmodule
