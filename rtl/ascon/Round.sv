`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Hung Nguyen
// Create Date: 04/12/2026 06:51:21 PM
// Module Name: Round
// Project Name: Ascon_128
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////

module Round 
    import ascon_pkg::*;
(
    input  logic [0:4][63:0] x_in,
    output logic [0:4][63:0] x_out,
    input  logic [7:0]       round_const
);
    logic [63:0] x0, x2, x4;
    logic [63:0] t0, t1, t2, t3, t4;
    
    always_comb begin
        // ADD ROUND CONSTANT
        x0 = x_in[0];
        // x1 = x_in[1];
        x2 = x_in[2] ^ {56'b0, round_const};
        // x3 = x_in[3];
        x4 = x_in[4];

        // SUBSTITUTION LAYER
        // Pre S-box
        x0 = x0 ^ x4;
        x2 = x2 ^ x_in[1];
        x4 = x4 ^ x_in[3];
        
        // Keccak S-box (non-linear layer)
        t0 = x0 ^ (~x_in[1] & x2);
        t1 = x_in[1] ^ (~x2 & x_in[3]);
        t2 = x2 ^ (~x_in[3] & x4);
        t3 = x_in[3] ^ (~x4 & x0);
        t4 = x4 ^ (~x0 & x_in[1]);
        
        // Post S-box
        t1 = t1 ^ t0;
        t0 = t0 ^ t4;
        t3 = t3 ^ t2;
        t2 = ~t2;

        // LINEAR DIFFUSION LAYER 
        x_out[0] = t0 ^ ROR(t0, 19) ^ ROR(t0, 28);
        x_out[1] = t1 ^ ROR(t1, 61) ^ ROR(t1, 39);
        x_out[2] = t2 ^ ROR(t2,  1) ^ ROR(t2,  6);
        x_out[3] = t3 ^ ROR(t3, 10) ^ ROR(t3, 17);
        x_out[4] = t4 ^ ROR(t4,  7) ^ ROR(t4, 41); 
    end

endmodule
