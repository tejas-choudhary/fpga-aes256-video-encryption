module sccb_master (
    input  wire clk,       // 27 MHz System Clock
    input  wire reset_n,
    output reg  scl,
    inout  wire sda,
    output reg  done
);

    // 27 MHz / (68 * 4) ≈ 99.2 kHz SCCB Clock
    reg [6:0] clk_div;
    wire      tick = (clk_div == 7'd67);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            clk_div <= 7'd0;
        else if (tick)
            clk_div <= 7'd0;
        else
            clk_div <= clk_div + 7'd1;
    end

    // Essential OV7670 RGB565 QVGA Register Table
    localparam [7:0] REG_COUNT = 8'd16;
    reg [7:0]  reg_index;
    reg [15:0] rom_data;

    always @(*) begin
        case (reg_index)
            8'd0:  rom_data = 16'h1280; // COM7: Reset all registers
            8'd1:  rom_data = 16'h1204; // COM7: Set RGB output
            8'd2:  rom_data = 16'h1100; // CLKRC: Use external clock directly
            8'd3:  rom_data = 16'h40D0; // COM15: RGB565 full range
            8'd4:  rom_data = 16'h0C04; // COM3: Enable scale (for QVGA)
            8'd5:  rom_data = 16'h3E19; // COM14: Divide PCLK for QVGA
            8'd6:  rom_data = 16'h703A; // SCALING_XSC
            8'd7:  rom_data = 16'h7135; // SCALING_YSC
            8'd8:  rom_data = 16'h7211; // SCALING_DCWCTR
            8'd9:  rom_data = 16'h73F1; // SCALING_PCLK_DIV
            8'd10: rom_data = 16'hA202; // SCALING_PCLK_DELAY
            8'd11: rom_data = 16'h3A04; // TSLB: Line buffer設定
            8'd12: rom_data = 16'h1418; // COM9: AGC ceiling 4x
            8'd13: rom_data = 16'h4F80; // MTX1: Color matrix
            8'd14: rom_data = 16'h5080; // MTX2: Color matrix
            8'd15: rom_data = 16'h589E; // MTXS: Matrix sign
            default: rom_data = 16'hFFFF;
        endcase
    end

    // SCCB State Machine
    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_BIT   = 3'd2,
                     S_ACK   = 3'd3,
                     S_STOP  = 3'd4,
                     S_DONE  = 3'd5;

    reg [2:0]  state;
    reg [1:0]  phase;
    reg [1:0]  byte_sel;   // 0: Device Addr (0x42), 1: Reg Addr, 2: Reg Val
    reg [2:0]  bit_idx;
    reg [7:0]  shift_byte;
    reg        sda_out;
    reg        sda_oe;

    assign sda = sda_oe ? sda_out : 1'bz;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= S_IDLE;
            phase      <= 2'd0;
            byte_sel   <= 2'd0;
            bit_idx    <= 3'd7;
            reg_index  <= 8'd0;
            shift_byte <= 8'h42;
            scl        <= 1'b1;
            sda_out    <= 1'b1;
            sda_oe     <= 1'b1;
            done       <= 1'b0;
        end else if (tick) begin
            case (state)
                S_IDLE: begin
                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;
                    if (reg_index < REG_COUNT) begin
                        state    <= S_START;
                        phase    <= 2'd0;
                        byte_sel <= 2'd0;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_START: begin
                    case (phase)
                        2'd0: begin sda_out <= 1'b1; scl <= 1'b1; phase <= 2'd1; end
                        2'd1: begin sda_out <= 1'b0; scl <= 1'b1; phase <= 2'd2; end
                        2'd2: begin sda_out <= 1'b0; scl <= 1'b0; phase <= 2'd0;
                                    shift_byte <= 8'h42; // OV7670 Write Address
                                    bit_idx    <= 3'd7;
                                    state      <= S_BIT;
                              end
                        default: phase <= 2'd0;
                    endcase
                end

                S_BIT: begin
                    case (phase)
                        2'd0: begin
                            sda_oe  <= 1'b1;
                            sda_out <= shift_byte[bit_idx];
                            scl     <= 1'b0;
                            phase   <= 2'd1;
                        end
                        2'd1: begin scl <= 1'b1; phase <= 2'd2; end
                        2'd2: begin scl <= 1'b1; phase <= 2'd3; end
                        2'd3: begin
                            scl   <= 1'b0;
                            phase <= 2'd0;
                            if (bit_idx == 3'd0)
                                state <= S_ACK;
                            else
                                bit_idx <= bit_idx - 3'd1;
                        end
                    endcase
                end

                S_ACK: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b0; scl <= 1'b0; phase <= 2'd1; end
                        2'd1: begin scl <= 1'b1; phase <= 2'd2; end
                        2'd2: begin scl <= 1'b1; phase <= 2'd3; end
                        2'd3: begin
                            scl   <= 1'b0;
                            phase <= 2'd0;
                            if (byte_sel == 2'd0) begin
                                byte_sel   <= 2'd1;
                                shift_byte <= rom_data[15:8];
                                bit_idx    <= 3'd7;
                                state      <= S_BIT;
                            end else if (byte_sel == 2'd1) begin
                                byte_sel   <= 2'd2;
                                shift_byte <= rom_data[7:0];
                                bit_idx    <= 3'd7;
                                state      <= S_BIT;
                            end else begin
                                state <= S_STOP;
                            end
                        end
                    endcase
                end

                S_STOP: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_out <= 1'b0; scl <= 1'b0; phase <= 2'd1; end
                        2'd1: begin sda_out <= 1'b0; scl <= 1'b1; phase <= 2'd2; end
                        2'd2: begin sda_out <= 1'b1; scl <= 1'b1; phase <= 2'd0;
                                    reg_index <= reg_index + 8'd1;
                                    state     <= S_IDLE;
                              end
                        default: phase <= 2'd0;
                    endcase
                end

                S_DONE: begin
                    done    <= 1'b1;
                    scl     <= 1'b1;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule