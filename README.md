# Hardware-Accelerated Real-Time Video Encryption on FPGA

An end-to-end cryptographic video edge node built on the **Sipeed Tang Nano 20K (Gowin GW2AR-18)** FPGA. Raw VGA/QVGA video is captured from an **OV7670 CMOS sensor** over a parallel DVP bus, bridged across asynchronous clock domains via Block RAM FIFO, encrypted in silicon using **AES-256-CTR**, and streamed over UDP via a **W5500 SPI-to-Ethernet** controller to a Python/OpenCV host receiver.

## System Architecture

```text
[OV7670 Camera] ──(8-bit DVP @ 24 MHz PCLK)──► [ov7670_capture]
                                                      │ (16-bit RGB565)
                                                      ▼
[Gowin rPLL (24 MHz)] ──► XCLK               [Dual-Clock Async FIFO]
[SCCB/I2C Master]     ──► SCL/SDA                     │ (27 MHz sys_clk)
                                                      ▼
                                             [pixel_packer_128]
                                                      │ (128-bit blocks)
                                                      ▼
[Laptop: receiver.py] ◄──(UDP Port 5005)──── [W5500 SPI Master] ◄── [AES-256-CTR Core]
