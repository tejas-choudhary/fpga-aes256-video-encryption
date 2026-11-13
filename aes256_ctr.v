`timescale 1ns/1ps
// One-block AES-256-CTR engine. Pulse start for one cycle when busy=0.
// ctr_block MUST be unique for every block encrypted with the same key.
module aes256_ctr (
    input wire clk, input wire reset,
    input wire start,
    input wire [255:0] key,
    input wire [127:0] ctr_block,
    input wire [127:0] plaintext,
    output reg [127:0] ciphertext,
    output reg done,
    output reg busy
);
    reg [255:0] key_reg;
    reg [127:0] counter_reg;
    reg [127:0] plaintext_reg;
    wire [127:0] keystream;

    aes256_core u_aes256 (
        .key(key_reg), .block_in(counter_reg), .block_out(keystream)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            key_reg <= 256'd0;
            counter_reg <= 128'd0;
            plaintext_reg <= 128'd0;
            ciphertext <= 128'd0;
            done <= 1'b0;
            busy <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                key_reg <= key;
                counter_reg <= ctr_block;
                plaintext_reg <= plaintext;
                busy <= 1'b1;
            end else if (busy) begin
                ciphertext <= plaintext_reg ^ keystream;
                done <= 1'b1;
                busy <= 1'b0;
            end
        end
    end
endmodule
