fpga-aes256-video-encryption/
├── rtl/
│   ├── camera_top.v
│   ├── ov7670_capture.v
│   ├── sccb_master.v
│   ├── pixel_packer_128.v
│   ├── aes256_core.v
│   ├── aes256_ctr.v
│   ├── w5500_spi_master.v
│   └── ip/
│       ├── gowin_rpll.v
│       └── fifo_hs.v
├── tb/
│   └── aes256_tb.v
├── constraints/
│   ├── camera_pin_conn.cst
│   └── SEC_project.sdc
├── software/
│   ├── receiver.py
│   └── requirements.txt
├── docs/
│   └── architecture_diagram.png   # Add your block diagram / PPT slides here
├── .gitignore
└── README.md# fpga-aes256-video-encryption
Real-time hardware-accelerated video encryption on a Sipeed Tang Nano 20K FPGA. Captures raw DVP video from an OV7670 camera, bridges clock domains via async BRAM FIFO, encrypts frames in silicon using AES-256-CTR, and streams UDP packets over a W5500 SPI-to-Ethernet module to a Python/OpenCV receiver.
