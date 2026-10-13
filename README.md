# CamPanel

**Español** · [English](#english)

Cliente nativo de macOS para cámaras IP compatibles con la API CGI de Foscam HD.
Sustituye al plugin del navegador que ya no funciona en el Mac: vídeo en directo,
control PTZ con posiciones guardadas y configuración de red y WiFi.

> Proyecto independiente. No está afiliado, respaldado ni patrocinado por Foscam.
> «Foscam» es marca de sus respectivos propietarios y se menciona solo para
> indicar compatibilidad.

## Características

- Vídeo en directo (MJPEG, con respaldo por fotos).
- Joystick PTZ (ratón o flechas del teclado), velocidad y posiciones con miniatura.
- Búsqueda automática de cámaras en la red local (según la máscara real, hasta /22).
- Foto instantánea guardada en `Imágenes/CamPanel`.
- Red: IP (DHCP/manual) y puertos. WiFi: buscar redes y conectar.
- Sistema: nombre, espejo, volteo, infrarrojos y reinicio.
- La contraseña se guarda en el Llavero de macOS, nunca en disco.
- Sin dependencias: Swift + WebKit, sin servicios con root ni Python.
- Interfaz en español e inglés (sigue el idioma del sistema; otros idiomas usan inglés).

## Compatibilidad

| Estado | Cámaras |
|---|---|
| Probada | Foscam FI9831P (V2) |
| Debería funcionar | Foscam HD que usen `CGIProxy.fcgi` (serie FI98xx, C1, C2, R2, R4…) |
| No funciona | Foscam antiguas (`decoder_control.cgi`) y otras marcas |

Si la pruebas con otro modelo, abre un *issue* con el resultado.

## Instalación

Requiere macOS 13 o posterior y Xcode o las Command Line Tools.

```bash
git clone https://github.com/ssoler01/campanel-mac.git
cd campanel-mac
bash build.sh
open build/CamPanel.app
```

La app se firma de forma *ad hoc*. Si macOS la bloquea la primera vez:
clic derecho ▸ Abrir. Al conectar, concede el permiso de **Red local**.

## Probar sin cámara

```bash
python3 tools/mock_camera.py   # 127.0.0.1:8089  usuario: admin  clave: test
```

## Aviso

Esta herramienta modifica la configuración de la cámara (IP, WiFi, puertos).
Un cambio erróneo puede dejarla inaccesible hasta restablecerla. Úsala bajo tu
responsabilidad; el software se ofrece «tal cual», sin garantía (ver `LICENSE`).

## Contribuir

Las ideas más útiles: soporte para más modelos, ONVIF y audio. Abre un *issue*
antes de un cambio grande.

## Licencia

MIT. Ver [LICENSE](LICENSE).

---

## English

Native macOS client for IP cameras compatible with the Foscam HD CGI API. It
replaces the browser plugin that no longer works on modern Macs: live video,
PTZ control with presets, and network/WiFi configuration.

> Independent project. Not affiliated with, endorsed or sponsored by Foscam.
> "Foscam" is a trademark of its respective owners and is mentioned only to
> indicate compatibility.

### Features

- Live video (MJPEG, with snapshot fallback).
- PTZ joystick (mouse or arrow keys), speed and presets with thumbnails.
- Automatic camera discovery on the local network (uses the real netmask, up to /22).
- One-click snapshot saved to `Pictures/CamPanel`.
- Network: IP (DHCP/manual) and ports. WiFi: scan and connect.
- System: name, mirror, flip, infrared LEDs and reboot.
- The password is stored in the macOS Keychain, never on disk.
- No dependencies: Swift + WebKit, no root services, no Python.
- Interface in Spanish and English (follows the system language; other languages fall back to English).

### Compatibility

| Status | Cameras |
|---|---|
| Tested | Foscam FI9831P (V2) |
| Should work | HD Foscam models using `CGIProxy.fcgi` (FI98xx, C1, C2, R2, R4…) |
| Not supported | Legacy Foscam (`decoder_control.cgi`) and other brands |

### Install

Requires macOS 13+ and Xcode or the Command Line Tools.

```bash
git clone https://github.com/ssoler01/campanel-mac.git
cd campanel-mac
bash build.sh
open build/CamPanel.app
```

The app is ad-hoc signed. If macOS blocks it the first time: right-click ▸ Open.
Grant the **Local Network** permission when connecting.

### Try it without a camera

```bash
python3 tools/mock_camera.py   # 127.0.0.1:8089  user: admin  password: test
```

### Disclaimer

This tool changes camera settings (IP, WiFi, ports). A wrong change can make the
camera unreachable until it is reset. Use at your own risk; the software is
provided "as is", without warranty (see `LICENSE`).

### License

MIT. See [LICENSE](LICENSE).
