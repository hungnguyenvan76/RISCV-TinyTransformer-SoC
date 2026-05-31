`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Hung Nguyen
// Create Date: 05/25/2026 08:51:27 AM
// Module Name: Ascon_Encrypt_tb
// Project Name: Ascon_128aead
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////

module Ascon_Encrypt_tb;

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
        reset_n = 0; start = 0; mode = 2'b00; skip_asso = 0;
        key   = 128'h08090a0b0c0d0e0f_0001020304050607; 
        nonce = 128'h08090a0b0c0d0e0f_0001020304050607;
        cipher_ready = 1; mess_valid = 0; message = 0; mess_last = 0;
        
        repeat(2) @(negedge clk);
        reset_n = 1;
    end
    endtask

    task start_crypto(input logic s_asso);
    begin
        skip_asso = s_asso;
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        // wait INIT done (wait pull or Msg)
        // wait(mess_pull == 1'b1);
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

    task wait_and_check(input string test_name, input logic [127:0] exp_tag);
    begin
        wait(done);
        if (out_tag == exp_tag)
            $display("[%0t] %s: PASS (Tag Match: %h)", $time, test_name, out_tag);
        else begin
            $display("[%0t] %s: FAIL", $time, test_name);
            $display("      Expected: %h", exp_tag);
            $display("      Got     : %h", out_tag);
        end
        repeat(2) @(negedge clk);
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
    
    
    // --- SCENARIO TEST ---
    initial begin
        reset_system();

        $display("========================================");
        $display("   STARTING ENCRYPT AUTO-TEST (10 TCs)  ");
        $display("========================================");

        // Test 1: Empty
        // start_crypto(.s_asso(1)); // skip AD

        // Test 4: 1 chunk AD, 1 chunk M (Partial)
        reset_system();
        start_crypto(0);
        send_data(str_to_le("ASCON128"), 1); 
        // wait(mess_pull == 1'b1); // Chờ chuyển miền xong
        send_data(str_to_le("helloasc"), 1);
        wait_and_check("Test 4 (AD:8B, M:8B)", 128'hb79bb3b7b59a7d21536cc1e027aaa4a9);

        // Test 5: Full Block AD (16B), Full Block M (16B)
        reset_system();
        start_crypto(0);
        send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 1); 
        // wait(mess_pull == 1'b1);
        send_data(str_to_le("hello_as"), 0); send_data(str_to_le("con_128b"), 1);
        wait_and_check("Test 5 (AD:16B, M:16B)", 128'hbe6c8d1a4f7e8d5e331ca2e9819349f5);

        // Test 6: AD 24B, M 8B
        reset_system();
        start_crypto(0);
        send_data(str_to_le("Associat"), 0); send_data(str_to_le("edData_O"), 0); send_data(str_to_le("ver16B!!"), 1);
        // wait(mess_pull == 1'b1);
        send_data(str_to_le("ShortMsg"), 1);
        wait_and_check("Test 6 (AD:24B, M:8B)", 128'h74360fccf2a037027c86b4b9d8c1d469);

        // Test 7: AD 8B, M 24B
        reset_system();
        start_crypto(0);
        send_data(str_to_le("ShortAD!"), 1);
        // wait(mess_pull == 1'b1);
        send_data(str_to_le("ThisIsAL"), 0); send_data(str_to_le("ongerMes"), 0); send_data(str_to_le("sageForT"), 1);
        wait_and_check("Test 7 (AD:8B, M:24B)", 128'h5df57ec89efb99f09251b365dd31af4c);

        // Test 8: AD 32B, M 32B
        reset_system();
        start_crypto(0);
        send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 0); send_data(str_to_le("ASCON_AE"), 0); send_data(str_to_le("AD_128b!"), 1);
        // wait(mess_pull == 1'b1);
        send_data(str_to_le("hello_as"), 0); send_data(str_to_le("con_128b"), 0); send_data(str_to_le("hello_as"), 0); send_data(str_to_le("con_128b"), 1);
        wait_and_check("Test 8 (AD:32B, M:32B)", 128'h2358b1d83bb88f6c99cfddd61e6ed82b);

        // Test 9: AD 16B, M 24B
        reset_system();
        start_crypto(0);
        send_data(str_to_le("AD_IsExa"), 0); send_data(str_to_le("ctly16B!"), 1);
        // wait(mess_pull == 1'b1);
        send_data(str_to_le("MessageI"), 0); send_data(str_to_le("sExactly"), 0); send_data(str_to_le("24Bytes!"), 1);
        wait_and_check("Test 9 (AD:16B, M:24B)", 128'he761de241f523fd7da7ffd15f2787ecb);

        $display("========================================");
        $display("        ENCRYPT TEST COMPLETED          ");
        $display("========================================");
        $finish;
    end
        // Monitor Cipher Output
    always @(posedge clk) begin
        if (cipher_push && cipher_ready) begin
            $display("[%0t] Output Cipher Chunk: %h", $time, cipher);
        end
    end
endmodule
