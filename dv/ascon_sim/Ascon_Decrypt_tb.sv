`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Hung Nguyen
// Create Date: 05/25/2026 08:51:27 AM
// Module Name: Ascon_Decrypt_tb
// Project Name: Ascon_128aead
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module Ascon_Decrypt_tb;

    import ascon_pkg::*;
    logic clk;
    logic reset_n;
    
    // Stream Interface
    logic        mess_valid;
    logic        mess_pull;
    logic [63:0] message;
    logic        mess_last;
    logic        cipher_push;
    logic        cipher_ready;
    logic [63:0] cipher;
    logic        cipher_last;

    // Control Interface
    logic         start;
    logic [127:0] key;
    logic [127:0] nonce;
    logic [1:0]   mode; 
    logic         skip_asso;
    logic [127:0] in_tag;
    logic [127:0] out_tag;
    logic         success_tag;
    logic         done;

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // UUT
    Ascon_Core uut (.*);

    task reset_system();
    begin
        reset_n = 0; start = 0; 
        mode = 2'b01; // Mode DECRYPT
        skip_asso = 0;
        key   = 128'h08090a0b0c0d0e0f_0001020304050607; 
        nonce = 128'h08090a0b0c0d0e0f_0001020304050607;
        cipher_ready = 1; mess_valid = 0; message = 0; mess_last = 0;
        in_tag = 128'd0;
        
        repeat(2) @(negedge clk);
        reset_n = 1;
    end
    endtask

    task start_crypto(input logic s_asso, input logic [127:0] exp_tag);
    begin
        skip_asso = s_asso;
        in_tag = exp_tag; // Load tag
        
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
    end
    endtask

    task send_data(input logic [63:0] data, input logic last);
    begin
        @(negedge clk);
        mess_valid = 1;
        message = data;
        mess_last = last;
        
        @(posedge clk);
        while (!mess_pull) @(posedge clk);
        
        @(negedge clk);
        mess_valid = 0; mess_last = 0; 
    end
    endtask

    task wait_and_check(input string test_name);
    begin
        wait(done);
        if (success_tag)
            $display("[%0t] %s: PASS (Authentication Success!)", $time, test_name);
        else begin
            $display("[%0t] %s: FAIL (Tag Mismatch/Forgery Detected)", $time, test_name);
        end
        repeat(5) @(negedge clk);
    end
    endtask
    
    function logic [63:0] str_to_le(input logic [63:0] str_in);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                str_to_le[i*8 +: 8] = str_in[(7-i)*8 +: 8];
            end
        end
    endfunction
    
    
    // --- SCENARIO TEST DECRYPT ---
    initial begin
        reset_system();

        $display("========================================");
        $display("   STARTING DECRYPT AUTO-TEST (10 TCs)  ");
        $display("========================================");

        // Test 4: AD(8B) - Message(8B)
        reset_system();
        start_crypto(0, 128'hb79bb3b7b59a7d21536cc1e027aaa4a9);
        send_data(str_to_le("ASCON128"), 1); 
        send_data(64'h766d747b615aafb2, 1);
        wait_and_check("Test 4 (AD:8B, Ciph:8B)");

        // Test 5: AD(16B) - Message(16B)
        reset_system();
        start_crypto(0, 128'hbe6c8d1a4f7e8d5e331ca2e9819349f5);
        send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 1); 
        send_data(64'h7b8ee935fb704bb0, 0); send_data(64'h2d55169b356354b0, 1);
        wait_and_check("Test 5 (AD:16B, Ciph:16B)");

        // Test 6: AD(24B) - Message(8B)
        reset_system();
        start_crypto(0, 128'h74360fccf2a037027c86b4b9d8c1d469);
        send_data(str_to_le("Associat"), 0); send_data(str_to_le("edData_O"), 0); send_data(str_to_le("ver16B!!"), 1);
        send_data(64'h0929df426b658f4a, 1);
        wait_and_check("Test 6 (AD:24B, Ciph:8B)");

        // Test 7: AD(8B) - Message(24B)
        reset_system();
        start_crypto(0, 128'h5df57ec89efb99f09251b365dd31af4c);
        send_data(str_to_le("ShortAD!"), 1);
        send_data(64'hcf3e4865c384e73d, 0); send_data(64'h25f769407d2a04e9, 0); send_data(64'h2a0e4d63b6878cc0, 1);
        wait_and_check("Test 7 (AD:8B, Ciph:24B)");

        // Test 8: AD(32B) - Message(32B)
        reset_system();
        start_crypto(0, 128'h2358b1d83bb88f6c99cfddd61e6ed82b);
        send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 0); send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 1);
        send_data(64'h15fd5bc119171b50, 0); send_data(64'hd7bd072babb90aed, 0); send_data(64'h0024b4f885a0170b, 0); send_data(64'h94bc022d11e2e2cb, 1);
        wait_and_check("Test 8 (AD:32B, Ciph:32B)");

        // Test 9: AD(16B) - Message(24B)
        reset_system();
        start_crypto(0, 128'he761de241f523fd7da7ffd15f2787ecb);
        send_data(str_to_le("AD_IsExa"), 0); send_data(str_to_le("ctly16B!"), 1);
        send_data(64'hca8de423450cf6c6, 0); send_data(64'h49c645cbc64dcc91, 0); send_data(64'hb41ad62e7a22e460, 1);
        wait_and_check("Test 9 (AD:16B, Ciph:24B)");

        $display("========================================");
        $display("        DECRYPT TEST COMPLETED          ");
        $display("========================================");
        $finish;
    end
    
    // Monitor Output: LPlaintext
    always @(posedge clk) begin
        if (cipher_push && cipher_ready) begin
            $display("[%0t] Output Plaintext Chunk: %h", $time, cipher);
        end
    end
endmodule
