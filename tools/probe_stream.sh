#!/bin/bash
# Diagnóstico: prueba qué rutas de vídeo acepta tu cámara.
# Pide la contraseña sin mostrarla y NO la imprime; solo muestra códigos HTTP,
# tipos de contenido y bytes recibidos. Se puede compartir la salida sin riesgo.
set -u

read -r -p "IP de la cámara [192.168.1.50]: " HOST; HOST=${HOST:-192.168.1.50}
read -r -p "Puerto [88]: " PORT; PORT=${PORT:-88}
read -r -p "Usuario: " USR
read -r -s -p "Contraseña: " PWD_RAW; echo

enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
U=$(enc "$USR"); W=$(enc "$PWD_RAW"); unset PWD_RAW

probe() {   # probe "nombre" "ruta con %U y %W" segundos
  local url="http://$HOST:$PORT${2//%U/$U}"; url="${url//%W/$W}"
  printf '%-34s ' "$1"
  curl -s -m "${3:-4}" -o /dev/null \
    -w 'HTTP %{http_code} | %{content_type} | %{size_download} bytes en %{time_total}s\n' "$url" \
    || true
}

echo
echo "Cámara: $HOST:$PORT"
echo "--- flujo de vídeo (4 s cada prueba) ---"
probe "CGIStream GetMJPEGStream"   "/cgi-bin/CGIStream.cgi?cmd=GetMJPEGStream&usr=%U&pwd=%W"
probe "CGIProxy GetMJPEGStream"    "/cgi-bin/CGIProxy.fcgi?cmd=GetMJPEGStream&usr=%U&pwd=%W"
probe "videostream.cgi"            "/videostream.cgi?user=%U&pwd=%W"
probe "mjpeg.cgi (alternativa)"    "/cgi-bin/mjpeg.cgi?user=%U&pwd=%W"
echo "--- fotos ---"
probe "snapPicture2" "/cgi-bin/CGIProxy.fcgi?cmd=snapPicture2&usr=%U&pwd=%W" 6
probe "snapPicture2 (2.ª)" "/cgi-bin/CGIProxy.fcgi?cmd=snapPicture2&usr=%U&pwd=%W" 6
echo "--- información (sin datos sensibles) ---"
curl -s -m 5 "http://$HOST:$PORT/cgi-bin/CGIProxy.fcgi?cmd=getDevInfo&usr=$U&pwd=$W" \
  | grep -oE '<(productName|firmwareVer|hardwareVer)>[^<]*' | sed 's/^</  /; s/>/: /'
echo
echo "Copia y pega esta salida (no contiene la contraseña)."
