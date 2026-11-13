# fpga-aes256-video-encryption
Real-time hardware-accelerated video encryption on a Sipeed Tang Nano 20K FPGA. Captures raw DVP video from an OV7670 camera, bridges clock domains via async BRAM FIFO, encrypts frames in silicon using AES-256-CTR, and streams UDP packets over a W5500 SPI-to-Ethernet module to a Python/OpenCV receiver.
