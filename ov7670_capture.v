module ov7670_capture (
    input  wire        pclk,
    input  wire        reset_n,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d_in,
    output reg  [15:0] pixel_data,
    output reg         pixel_valid,
    output reg         frame_done
);

    reg       byte_toggle;
    reg [7:0] byte_latched;

    always @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            byte_toggle  <= 1'b0;
            byte_latched <= 8'd0;
            pixel_data   <= 16'd0;
            pixel_valid  <= 1'b0;
            frame_done   <= 1'b0;
        end else begin
            pixel_valid <= 1'b0;
            frame_done  <= 1'b0;

            if (vsync) begin
                // VSYNC high indicates end of frame / start of vertical blanking
                byte_toggle <= 1'b0;
                frame_done  <= 1'b1;
            end else if (href) begin
                // Active line of pixels
                if (byte_toggle == 1'b0) begin
                    byte_latched <= d_in;
                    byte_toggle  <= 1'b1;
                end else begin
                    pixel_data  <= {byte_latched, d_in};
                    pixel_valid <= 1'b1; // Pulse high to write into Async FIFO
                    byte_toggle <= 1'b0;
                end
            end else begin
                byte_toggle <= 1'b0;
            end
        end
    end

endmodule