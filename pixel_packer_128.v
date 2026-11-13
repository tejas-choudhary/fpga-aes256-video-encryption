module pixel_packer_128 (
    input  wire         clk,            // 27 MHz System Clock
    input  wire         reset_n,
    
    // Interface to FIFO_HS_Top Read Port
    input  wire         fifo_empty,
    input  wire [15:0]  fifo_dout,
    output reg          fifo_rd_en,
    
    // Interface to AES-256 Core
    input  wire         aes_ready,      // High when AES core can accept a block
    output reg  [127:0] aes_block_out,
    output reg          aes_block_valid
);

    reg [2:0] pixel_count;
    reg       fifo_data_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_rd_en      <= 1'b0;
            fifo_data_valid <= 1'b0;
            pixel_count     <= 3'd0;
            aes_block_out   <= 128'd0;
            aes_block_valid <= 1'b0;
        end else begin
            fifo_rd_en      <= 1'b0;
            aes_block_valid <= 1'b0;

            if (!fifo_empty && aes_ready && !fifo_rd_en) begin
                fifo_rd_en <= 1'b1;
            end

            fifo_data_valid <= fifo_rd_en;

            if (fifo_data_valid) begin
                aes_block_out <= {aes_block_out[111:0], fifo_dout};
                if (pixel_count == 3'd7) begin
                    pixel_count     <= 3'd0;
                    aes_block_valid <= 1'b1;
                end else begin
                    pixel_count <= pixel_count + 3'd1;
                end
            end
        end
    end

endmodule