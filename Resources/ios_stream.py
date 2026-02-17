#!/usr/bin/env python3
"""
Persistent iOS screen streaming via pymobiledevice3.
Connects once via tunneld, then continuously captures screenshots,
compresses to JPEG, and writes length-prefixed data to stdout.

Protocol: [4 bytes big-endian length][JPEG data] repeated
"""

import sys
import struct
import time
import json
import asyncio
import urllib.request
import io


def get_tunnel_info(udid=None):
    """Get tunnel address/port from tunneld HTTP API."""
    try:
        resp = urllib.request.urlopen('http://127.0.0.1:49151/', timeout=3)
        tunnels = json.loads(resp.read())
        if udid:
            # Try with and without dashes
            udid_nodash = udid.replace('-', '')
            for dev_udid, tunnel_list in tunnels.items():
                if dev_udid == udid or dev_udid.replace('-', '') == udid_nodash:
                    if tunnel_list:
                        return tunnel_list[0], dev_udid
        for dev_udid, tunnel_list in tunnels.items():
            if tunnel_list:
                return tunnel_list[0], dev_udid
    except Exception as e:
        sys.stderr.write(f"Tunneld query failed: {e}\n")
    return None, None


def png_to_jpeg(png_data, quality=70):
    """Convert PNG data to smaller JPEG for faster pipe transfer."""
    try:
        from PIL import Image
        img = Image.open(io.BytesIO(png_data))
        # Downscale to half resolution for speed
        new_w = img.width // 2
        new_h = img.height // 2
        img = img.resize((new_w, new_h), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format='JPEG', quality=quality)
        return buf.getvalue()
    except Exception:
        return png_data


async def stream(udid=None):
    tunnel_info, resolved_udid = get_tunnel_info(udid)
    if not tunnel_info:
        sys.stderr.write("ERROR: No tunnel available. Is tunneld running?\n")
        sys.stderr.flush()
        sys.exit(1)

    tunnel_addr = tunnel_info['tunnel-address']
    tunnel_port = tunnel_info['tunnel-port']
    sys.stderr.write(f"Connecting to {resolved_udid} via [{tunnel_addr}]:{tunnel_port}\n")
    sys.stderr.flush()

    from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
    from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
    from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot

    rsd = RemoteServiceDiscoveryService((tunnel_addr, tunnel_port))
    await rsd.connect()
    sys.stderr.write(f"RSD connected: {rsd.udid}\n")
    sys.stderr.flush()

    stdout = sys.stdout.buffer

    with DvtSecureSocketProxyService(lockdown=rsd) as dvt:
        screenshot = Screenshot(dvt)
        sys.stderr.write("STREAMING\n")
        sys.stderr.flush()

        frame_count = 0
        start_time = time.time()

        while True:
            try:
                png_data = screenshot.get_screenshot()
                # Compress to JPEG and downscale for faster transfer
                jpeg_data = png_to_jpeg(png_data)
                length = len(jpeg_data)
                stdout.write(struct.pack('>I', length))
                stdout.write(jpeg_data)
                stdout.flush()

                frame_count += 1
                if frame_count % 10 == 0:
                    elapsed = time.time() - start_time
                    fps = frame_count / elapsed
                    sys.stderr.write(f"fps={fps:.1f} frames={frame_count}\n")
                    sys.stderr.flush()

            except BrokenPipeError:
                break
            except Exception as e:
                sys.stderr.write(f"Frame error: {e}\n")
                sys.stderr.flush()
                time.sleep(0.5)


def main():
    udid = sys.argv[1] if len(sys.argv) > 1 else None
    asyncio.run(stream(udid))


if __name__ == '__main__':
    main()
