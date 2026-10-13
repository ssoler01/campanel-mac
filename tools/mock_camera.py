#!/usr/bin/env python3
"""Cámara simulada (API estilo Foscam HD) para probar CamPanel sin una real.

    python3 tools/mock_camera.py            # usuario: admin  clave: test  puerto: 8089

Imita CGIProxy.fcgi (getDevInfo, red, WiFi, PTZ, presets...) y el MJPEG.
La imagen de prueba se genera sola (degradado) con zlib + sips (macOS).
"""
import http.server
import socketserver
import time
import urllib.parse
from pathlib import Path

import os
USER, PWD, PORT = "admin", os.environ.get("MOCK_PWD", "test"), int(os.environ.get("MOCK_PORT", "8089"))


def make_frame() -> bytes:
    """Escena sencilla 640x360 (salón esquemático) en Python puro; sips la pasa a JPEG."""
    import struct, subprocess, tempfile, zlib
    w, h = 640, 360

    def px(x, y):
        if 60 <= x < 360 and 205 <= y < 300:                    # sofá
            return (96, 118, 150) if (y < 235 or x < 78 or x >= 342) else (78, 98, 128)
        if 440 <= x < 580 and 50 <= y < 200:                    # ventana
            if x in range(508, 512) or y in range(122, 126) or x < 444 or x >= 576 or y < 54 or y >= 196:
                return (240, 240, 240)
            return (150 + (y - 50) // 5, 190 + (y - 50) // 8, 235)
        if 380 <= x < 396 and 120 <= y < 250:                   # lámpara de pie
            return (60, 60, 60) if y > 150 else (250, 232, 170)
        if y >= 262:                                            # suelo
            return (122 - (y - 262) // 4, 92 - (y - 262) // 5, 70)
        return (222 - y // 12, 212 - y // 12, 198 - y // 14)    # pared

    rows = b"".join(
        b"\x00" + b"".join(bytes(px(x, y)) for x in range(w)) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    with tempfile.TemporaryDirectory() as d:
        src, dst = Path(d, "f.png"), Path(d, "f.jpg")
        src.write_bytes(png)
        subprocess.run(["sips", "-s", "format", "jpeg", str(src), "--out", str(dst)],
                       check=True, capture_output=True)
        return dst.read_bytes()


FRAME = make_frame()
state = {
    "name": "Salon", "dhcp": "0", "ip": "192.168.1.50", "mask": "255.255.255.0",
    "gate": "192.168.1.1", "dns1": "192.168.1.1", "dns2": "8.8.8.8",
    "mirror": "0", "flip": "0", "ir": "0", "speed": "2",
    "presets": ["Puerta", "Sofa", "Ventana"], "wifi_ssid": "Casa_5G",
}


def xml(**kv):
    body = "".join(f"<{k}>{v}</{k}>" for k, v in kv.items())
    return f"<CGI_Result><result>0</result>{body}</CGI_Result>".encode()


def handle(cmd, q):
    g = lambda k: q.get(k, [""])[0]
    if cmd == "getDevInfo":
        return xml(productName="FI9831P", serialNo="C1D2E3F4A5B6", devName=state["name"],
                   mac="C0:62:6B:12:34:56", firmwareVer="2.11.1.120", hardwareVer="1.0.3.2")
    if cmd == "getDevName": return xml(devName=state["name"])
    if cmd == "setDevName": state["name"] = g("devName"); return xml()
    if cmd == "getIPInfo":
        return xml(isDHCP=state["dhcp"], ip=state["ip"], mask=state["mask"], gate=state["gate"],
                   dns1=state["dns1"], dns2=state["dns2"])
    if cmd == "setIpInfo":
        state.update(dhcp=g("isDHCP"), mask=g("mask"), gate=g("gate"), dns1=g("dns1"), dns2=g("dns2"))
        return xml()
    if cmd == "getPortInfo": return xml(webPort=89, httpsPort=443, mediaPort=88, onvifPort=888)
    if cmd == "setPortInfo": return xml()
    if cmd == "getWifiConfig":
        return xml(isEnable=1, isUseWifi=1, isConnected=1, ssid=state["wifi_ssid"], connectedAP=state["wifi_ssid"])
    if cmd == "refreshWifiList": return xml()
    if cmd == "getWifiList":
        aps = ["Casa_5G+aa:bb:cc:00:00:01+78+3", "Casa_2G+aa:bb:cc:00:00:02+64+3",
               "MOVISTAR_8F21+aa:bb:cc:00:00:03+41+3", "Invitados+aa:bb:cc:00:00:04+30+0"]
        return xml(totalCnt=len(aps), curCnt=len(aps), **{f"ap{i}": a for i, a in enumerate(aps)})
    if cmd == "setWifiSetting": state["wifi_ssid"] = g("ssid"); return xml()
    if cmd == "getPTZSpeed": return xml(speed=state["speed"])
    if cmd == "setPTZSpeed": state["speed"] = g("speed"); return xml()
    if cmd == "getPTZPresetPointList":
        return xml(cnt=len(state["presets"]), **{f"point{i}": p for i, p in enumerate(state["presets"])})
    if cmd == "ptzAddPresetPoint": state["presets"].append(g("name")); return xml()
    if cmd == "ptzDeletePresetPoint":
        state["presets"] = [p for p in state["presets"] if p != g("name")]; return xml()
    if cmd.startswith("ptz") or cmd in ("rebootSystem",): return xml()
    if cmd == "getMirrorAndFlipSetting": return xml(isMirror=state["mirror"], isFlip=state["flip"])
    if cmd == "mirrorVideo": state["mirror"] = g("isMirror"); return xml()
    if cmd == "flipVideo": state["flip"] = g("isFlip"); return xml()
    if cmd == "getInfraLedConfig": return xml(mode=state["ir"])
    if cmd == "setInfraLedConfig": state["ir"] = g("mode"); return xml()
    if cmd in ("openInfraLed", "closeInfraLed"): return xml()
    return xml()


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if q.get("usr", [""])[0] != USER or q.get("pwd", [""])[0] != PWD:
            body = b"<CGI_Result><result>-2</result></CGI_Result>"
            self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
            return self.wfile.write(body)
        cmd = q.get("cmd", [""])[0]
        if u.path.endswith("CGIStream.cgi") and cmd == "GetMJPEGStream":
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace;boundary=ipcamera")
            self.end_headers()
            try:
                while True:
                    self.wfile.write(b"--ipcamera\r\nContent-Type: image/jpeg\r\nContent-Length: "
                                     + str(len(FRAME)).encode() + b"\r\n\r\n" + FRAME + b"\r\n")
                    time.sleep(0.1)
            except (BrokenPipeError, ConnectionResetError):
                return
        if cmd == "snapPicture2":
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(FRAME))); self.end_headers()
            return self.wfile.write(FRAME)
        body = handle(cmd, q)
        self.send_response(200); self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)


class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"Cámara simulada en 127.0.0.1:{PORT}  usuario={USER} clave={PWD}")
    S(("127.0.0.1", PORT), H).serve_forever()
