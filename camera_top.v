module camera_top (
    input  wire       sys_clk,          // 27 MHz Tang Nano 20K Clock (Pin 4)
    input  wire       reset_n,          // Active-low Reset Button (Pin 88)

    // OV7670 Physical Pins (16 pins)
    input  wire       cam_pclk,
    input  wire       cam_vsync,
    input  wire       cam_href,
    input  wire [7:0] cam_d,
    output wire       cam_xclk,
    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_pwdn,
    output wire       cam_rst_n,

    // W5500 SPI Ethernet Physical Pins (5 pins)
    output wire       w5500_rst_n,
    output wire       w5500_cs_n,
    output wire       w5500_sclk,
    output wire       w5500_mosi,
    input  wire       w5500_miso,

    // Onboard Status LEDs (2 pins)
    output wire       init_done_led,    // Solid ON when OV7670 SCCB init finishes
    output wire       tx_activity_led   // Flickers as 1024B UDP packets transmit
);

    // Matches receiver.py:
    // AES_KEY   = b"0123456789abcdef0123456789abcdef"
    // AES_NONCE = b"1234567890abcdef"
    localparam [255:0] AES_KEY_HEX   = 256'h30313233343536373839616263646566_30313233343536373839616263646566;
    localparam [127:0] AES_NONCE_HEX = 128'h31323334_35363738_39306162_63646566;

    // Keep camera awake permanently
    assign cam_pwdn  = 1'b0;
    assign cam_rst_n = 1'b1;

    wire [15:0]  capture_data;
    wire         capture_valid;
    wire         frame_sync;
    wire         fifo_empty;
    wire         fifo_full;
    wire         fifo_rd_en;
    wire [15:0]  fifo_dout;

    // Packer <-> AES-256-CTR <-> W5500 SPI Internal Buses
    wire         aes_ready;
    wire [127:0] aes_plaintext_block;
    wire         aes_block_valid;
    wire [127:0] aes_ciphertext_block;
    wire         aes_done;
    wire         aes_busy;
    wire         spi_ready;

    assign aes_ready = (~aes_busy) && spi_ready;

    // Synchronize cam_vsync into sys_clk domain to reset CTR block per frame
    reg [1:0] vsync_sync;
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            vsync_sync <= 2'b00;
        else
            vsync_sync <= {vsync_sync[0], cam_vsync};
    end

    // 128-bit Counter Block Manager (Resets each frame, increments per encrypted block)
    reg [127:0] ctr_block_reg;
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n) begin
            ctr_block_reg <= AES_NONCE_HEX;
        end else if (vsync_sync[1]) begin
            ctr_block_reg <= AES_NONCE_HEX;
        end else if (aes_done) begin
            ctr_block_reg <= ctr_block_reg + 128'd1;
        end
    end

    // 1. 27 MHz to 24 MHz Clock Defibrillator
    Gowin_rPLL u_pll (
        .clkout (cam_xclk),
        .clkin  (sys_clk)
    );

    // 2. SCCB / I2C Register Initializer
    sccb_master u_sccb (
        .clk     (sys_clk),
        .reset_n (reset_n),
        .scl     (cam_scl),
        .sda     (cam_sda),
        .done    (init_done_led)
    );

    // 3. 8-bit to 16-bit DVP Pixel Capture (24 MHz PCLK Domain)
    ov7670_capture u_capture (
        .pclk        (cam_pclk),
        .reset_n     (reset_n),
        .vsync       (cam_vsync),
        .href        (cam_href),
        .d_in        (cam_d),
        .pixel_data  (capture_data),
        .pixel_valid (capture_valid),
        .frame_done  (frame_sync)
    );

    // 4. Dual-Clock Asynchronous FIFO (24 MHz PCLK to 27 MHz SYS_CLK)
    FIFO_HS_Top u_fifo (
        .Data         (capture_data),
        .WrClk        (cam_pclk),
        .RdClk        (sys_clk),
        .WrEn         (capture_valid),
        .RdEn         (fifo_rd_en),
        .Q            (fifo_dout),
        .Empty        (fifo_empty),
        .Full         (fifo_full),
        .Almost_Empty (),
        .Almost_Full  ()
    );

    // 5. 16-bit to 128-bit Block Packer
    pixel_packer_128 u_packer (
        .clk             (sys_clk),
        .reset_n         (reset_n),
        .fifo_empty      (fifo_empty),
        .fifo_dout       (fifo_dout),
        .fifo_rd_en      (fifo_rd_en),
        .aes_ready       (aes_ready),
        .aes_block_out   (aes_plaintext_block),
        .aes_block_valid (aes_block_valid)
    );

    // 6. Hardware AES-256-CTR Encryption Engine
    aes256_ctr u_aes_ctr (
        .clk        (sys_clk),
        .reset      (~reset_n),
        .start      (aes_block_valid),
        .key        (AES_KEY_HEX),
        .ctr_block  (ctr_block_reg),
        .plaintext  (aes_plaintext_block),
        .ciphertext (aes_ciphertext_block),
        .done       (aes_done),
        .busy       (aes_busy)
    );

    // 7. W5500 SPI Master UDP Transmitter
    w5500_spi_master u_w5500 (
        .clk            (sys_clk),
        .reset_n        (reset_n),
        .aes_ciphertext (aes_ciphertext_block),
        .aes_done       (aes_done),
        .spi_ready      (spi_ready),
        .w5500_rst_n    (w5500_rst_n),
        .w5500_cs_n     (w5500_cs_n),
        .w5500_sclk     (w5500_sclk),
        .w5500_mosi     (w5500_mosi),
        .w5500_miso     (w5500_miso),
        .tx_led         (tx_activity_led)
    );

endmodule