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


1. FPGA Bitstream (Gowin EDA)
Create a new Gowin EDA project targeting GW2AR-LV18QN88C8/I7.

Add all .v files from rtl/ and rtl/ip/ (exclude tb/aes256_tb.v), plus both files in constraints/.

Set camera_top as the Top Module, run Synthesize and Place & Route, and flash the generated .fs bitstream via Gowin Programmer.

2. Host Decryption & Video Display (Python)
Set your PC's Ethernet adapter to static IP 192.168.1.10 (255.255.255.0).

Install dependencies and launch the receiver:

Bash
cd software
pip install -r requirements.txt
python receiver.py
