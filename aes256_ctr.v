`timescale 1ns/1ps
// Iterative 14-round AES-256-CTR engine. Pulse start for one cycle when busy=0.
// Preserves exact module port interface while reducing LUT usage by >14x.
module aes256_ctr (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [127:0] ctr_block,
    input  wire [127:0] plaintext,
    output reg  [127:0] ciphertext,
    output reg          done,
    output reg          busy
);

    reg [3:0]   round_cnt;
    reg [127:0] state_reg;
    reg [127:0] k_prev_reg;
    reg [127:0] k_curr_reg;
    reg [7:0]   rcon_reg;
    reg [127:0] plaintext_reg;

    wire [127:0] next_state;
    wire [127:0] next_k_curr;
    wire [7:0]   next_rcon;
    wire         is_final_round = (round_cnt == 4'd14);

    aes256_core u_aes_round (
        .state_in    (state_reg),
        .k_prev_in   (k_prev_reg),
        .k_curr_in   (k_curr_reg),
        .rcon_in     (rcon_reg),
        .odd_round   (round_cnt[0]),
        .final_round (is_final_round),
        .state_out   (next_state),
        .k_next_out  (next_k_curr),
        .rcon_out    (next_rcon)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            round_cnt     <= 4'd0;
            state_reg     <= 128'd0;
            k_prev_reg    <= 128'd0;
            k_curr_reg    <= 128'd0;
            rcon_reg      <= 8'h01;
            plaintext_reg <= 128'd0;
            ciphertext    <= 128'd0;
            done          <= 1'b0;
            busy          <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                // Round 0 initial AddRoundKey happens immediately upon latching
                state_reg     <= ctr_block ^ key[255:128];
                k_prev_reg    <= key[255:128];
                k_curr_reg    <= key[127:0];
                rcon_reg      <= 8'h01;
                plaintext_reg <= plaintext;
                round_cnt     <= 4'd1;
                busy          <= 1'b1;
            end else if (busy) begin
                if (is_final_round) begin
                    ciphertext <= plaintext_reg ^ next_state;
                    done       <= 1'b1;
                    busy       <= 1'b0;
                    round_cnt  <= 4'd0;
                end else begin
                    state_reg  <= next_state;
                    k_prev_reg <= k_curr_reg;
                    k_curr_reg <= next_k_curr;
                    rcon_reg   <= next_rcon;
                    round_cnt  <= round_cnt + 4'd1;
                end
            end
        end
    end

endmodule
