import socket
import struct
import time
import argparse
import numpy as np
import cv2
from Crypto.Cipher import AES
from Crypto.Util import Counter


# Cryptography Testbench Vector (from aes256_tb.v)
AES_KEY = bytes.fromhex(
    "000102030405060708090a0b0c0d0e0f"
    "101112131415161718191a1b1c1d1e1f"
)
TB_CTR_BLOCK = bytes.fromhex("00112233445566778899aabbccddeeff")
TB_PLAINTEXT = bytes.fromhex("00000000000000000000000000000000")
TB_EXPECTED_CIPHERTEXT = bytes.fromhex("8ea2b7ca516745bfeafc49904b496089")

# Video settings (OV7670 standard VGA or QVGA)
FRAME_WIDTH = 320   # Change to 640 if capturing full VGA
FRAME_HEIGHT = 240  # Change to 480 if capturing full VGA
BYTES_PER_PIXEL = 2 # RGB565 = 16 bits (2 bytes) per pixel


def verify_hardware_testbench():
    """
    Verifies that Python's AES-256-CTR implementation produces the exact
    same 128-bit output as aes256_tb.v before starting the video server.
    """
    print("--- Running Hardware Testbench Vector Verification ---")
    init_val = int.from_bytes(TB_CTR_BLOCK, byteorder="big")
    ctr = Counter.new(128, initial_value=init_val)
    cipher = AES.new(AES_KEY, AES.MODE_CTR, counter=ctr)

    ciphertext = cipher.encrypt(TB_PLAINTEXT)
    print(f"Key        : {AES_KEY.hex()}")
    print(f"Counter    : {TB_CTR_BLOCK.hex()}")
    print(f"Plaintext  : {TB_PLAINTEXT.hex()}")
    print(f"Ciphertext : {ciphertext.hex()}")
    print(f"Expected   : {TB_EXPECTED_CIPHERTEXT.hex()}")

    if ciphertext == TB_EXPECTED_CIPHERTEXT:
        print("[SUCCESS] Python AES-256-CTR matches Verilog testbench 100%!\n")
    else:
        raise ValueError("[ERROR] Mismatch between Python and Verilog testbench!")


def decrypt_aes256_ctr_payload(ctr_block_bytes: bytes, encrypted_payload: bytes) -> bytes:
    """
    Decrypts an arbitrary-length payload using AES-256-CTR starting at ctr_block_bytes.
     assumes the FPGA increments the 128-bit counter by +1 for every 16-byte block.
    """
    init_val = int.from_bytes(ctr_block_bytes, byteorder="big")
    ctr = Counter.new(128, initial_value=init_val)
    cipher = AES.new(AES_KEY, AES.MODE_CTR, counter=ctr)
    return cipher.decrypt(encrypted_payload)


def rgb565_to_bgr888(rgb565_bytes: bytes, width: int, height: int, big_endian: bool = True) -> np.ndarray:
    """
    Converts raw 16-bit RGB565 byte buffer from OV7670 into an 8-bit BGR image for OpenCV.
    OV7670 sends MSB first over DVP, so big_endian=True is standard.
    """
    dtype = ">u2" if big_endian else "<u2"
    pixels = np.frombuffer(rgb565_bytes, dtype=dtype).reshape((height, width))

    # Extract 5-bit Red, 6-bit Green, 5-bit Blue and scale to 8-bit (0-255)
    r = ((pixels >> 11) & 0x1F) << 3
    g = ((pixels >> 5)  & 0x3F) << 2
    b = (pixels         & 0x1F) << 3

    # Optional: Fill lower bits for smoother dynamic range
    r |= (r >> 5)
    g |= (g >> 6)
    b |= (b >> 5)

    bgr_frame = np.dstack((b, g, r)).astype(np.uint8)
    return bgr_frame



def run_udp_receiver(ip: str, port: int, width: int, height: int):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((ip, port))
    sock.settimeout(0.5)

    print(f"[COMMAND CENTER] Listening for encrypted FPGA packets on UDP {ip}:{port}...")
    print(f"[VIDEO CONFIG]   Resolution: {width}x{height} (RGB565, {width*2} bytes/line)")
    print("Press 'q' in the video window to exit.\n")

    frame_buffer = np.zeros((height, width, 3), dtype=np.uint8)
    raw_cipher_view = np.zeros((height, width, 3), dtype=np.uint8)
    line_byte_len = width * BYTES_PER_PIXEL

    packets_received = 0
    fps_time = time.time()
    frames_completed = 0
    current_fps = 0.0

    while True:
        try:
            packet, addr = sock.recvfrom(2048)
            packets_received += 1

            # Case A: Packet has 18-byte Header [2B Line_Num + 16B CTR_Block + Encrypted_Line]
            if len(packet) == 18 + line_byte_len:
                line_num = struct.unpack(">H", packet[0:2])[0]
                ctr_block = packet[2:18]
                ciphertext = packet[18:]

                if 0 <= line_num < height:
                    # 1. Visualize raw encrypted noise (GREAT for Slide 3 / Live Demo!)
                    cipher_line_bgr = rgb565_to_bgr888(ciphertext, width, 1)
                    raw_cipher_view[line_num, :, :] = cipher_line_bgr[0, :, :]

                    # 2. Decrypt via AES-256-CTR and render clean RGB565 line
                    plaintext = decrypt_aes256_ctr_payload(ctr_block, ciphertext)
                    clean_line_bgr = rgb565_to_bgr888(plaintext, width, 1)
                    frame_buffer[line_num, :, :] = clean_line_bgr[0, :, :]

                    if line_num == height - 1:
                        frames_completed += 1

        except socket.timeout:
            pass

        # Calculate FPS
        now = time.time()
        if now - fps_time >= 1.0:
            current_fps = frames_completed / (now - fps_time)
            frames_completed = 0
            fps_time = now

        # Combine Encrypted Noise (Left) and Decrypted Video (Right) side-by-side for Demo!
        combined_display = np.hstack((raw_cipher_view, frame_buffer))
        cv2.putText(
            combined_display,
            f"INTERCEPTED STREAM (AES-256 NOISE)",
            (10, 22),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 255),
            2,
        )
        cv2.putText(
            combined_display,
            f"DECRYPTED STREAM ({current_fps:.1f} FPS | PKTS: {packets_received})",
            (width + 10, 22),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 255, 0),
            2,
        )

        cv2.imshow("Tang Nano 20K - AES-256 Edge Node Command Center", combined_display)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    sock.close()
    cv2.destroyAllWindows()


# Built-in simulator for testing the Command Center
def simulate_fpga_transmitter(ip: str, port: int, width: int, height: int):
    """
    Simulates the Tang Nano 20K + OV7670 + W5500 by generating synthetic RGB565
    frames (or using your webcam), encrypting them with AES-256-CTR, and blasting
    them over UDP to the Command Center receiver.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    global_counter = int.from_bytes(TB_CTR_BLOCK, byteorder="big")
    frame_idx = 0

    print(f"[SIMULATOR] Sending encrypted AES-256-CTR RGB565 packets to {ip}:{port}...")
    try:
        while True:
            # Generate a test pattern frame in BGR888
            img = np.zeros((height, width, 3), dtype=np.uint8)
            # Moving color gradient + bouncing box
            x_pos = (frame_idx * 5) % (width - 60)
            cv2.rectangle(img, (x_pos, 60), (x_pos + 60, 140), (0, 255, 180), -1)
            cv2.putText(
                img,
                f"TANG NANO 20K LIVE #{frame_idx}",
                (20, height - 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (255, 255, 255),
                2,
            )

            # Convert BGR888 -> RGB565 (Big Endian, matching OV7670)
            b = (img[:, :, 0].astype(np.uint16) >> 3) & 0x1F
            g = (img[:, :, 1].astype(np.uint16) >> 2) & 0x3F
            r = (img[:, :, 2].astype(np.uint16) >> 3) & 0x1F
            rgb565 = ((r << 11) | (g << 5) | b).astype(">u2")

            # Encrypt and send line-by-line
            for line_num in range(height):
                raw_line_bytes = rgb565[line_num].tobytes()
                ctr_bytes = global_counter.to_bytes(16, byteorder="big")

                # Encrypt line using AES-256-CTR
                ciphertext = decrypt_aes256_ctr_payload(ctr_bytes, raw_line_bytes)

                # Advance counter by number of 128-bit (16-byte) blocks in this line
                blocks_per_line = len(raw_line_bytes) // 16
                global_counter = (global_counter + blocks_per_line) & ((1 << 128) - 1)

                # Pack [2B line_num][16B ctr_block][Encrypted RGB565 bytes]
                packet = struct.pack(">H", line_num) + ctr_bytes + ciphertext
                sock.sendto(packet, (ip, port))

            frame_idx += 1
            time.sleep(1 / 30.0)  # ~30 FPS
    except KeyboardInterrupt:
        print("\n[SIMULATOR] Stopped.")
    finally:
        sock.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AES-256-CTR FPGA Video Command Center")
    parser.add_argument("--ip", type=str, default="127.0.0.1", help="UDP listen/target IP (use 0.0.0.0 for W5500)")
    parser.add_argument("--port", type=int, default=5005, help="UDP port")
    parser.add_argument("--simulate-tx", action="store_true", help="Run simulated FPGA transmitter for testing")
    args = parser.parse_args()

    #verify testbench vector
    verify_hardware_testbench()

    #run either the receiver or the simulator
    if args.simulate_tx:
        simulate_fpga_transmitter(args.ip, args.port, FRAME_WIDTH, FRAME_HEIGHT)
    else:
        run_udp_receiver(args.ip, args.port, FRAME_WIDTH, FRAME_HEIGHT)