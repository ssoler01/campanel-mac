"use strict";
/* Idiomas: español (texto original) e inglés. Cualquier otro idioma usa inglés. */
const LANG = (navigator.languages?.[0] || navigator.language || "en").toLowerCase().startsWith("es") ? "es" : "en";
document.documentElement.lang = LANG;

const EN = {
  // conexión
  "Conecta con tu cámara": "Connect to your camera", "Dirección IP": "IP address", "Puerto": "Port",
  "Usuario": "User", "Contraseña": "Password", "Recordar en el Llavero": "Remember in Keychain",
  "Conectar": "Connect", "Conectando…": "Connecting…", "Cámara": "Camera",
  "o": "or", "Buscar cámaras en la red": "Find cameras on the network", "Buscando cámaras…": "Looking for cameras…",
  "puerto {port}": "port {port}",
  "No se detectó ninguna red local. Comprueba que el Mac está conectado.": "No local network detected. Check that the Mac is connected.",
  "No se encontró ninguna cámara compatible. Comprueba que el Mac y la cámara están en la misma red.": "No compatible camera found. Check that the Mac and the camera are on the same network.",
  // barra lateral
  "En vivo": "Live", "Red": "Network", "WiFi": "WiFi", "Sistema": "System",
  "Conectada": "Connected", "Reconectando…": "Reconnecting…", "Sin conexión": "Offline",
  "Desconectar": "Disconnect",
  "¿Desconectar?": "Disconnect?",
  "Se borrarán las credenciales guardadas en el Llavero.": "The credentials saved in the Keychain will be deleted.",
  // en vivo
  "Guardar foto en Imágenes": "Save photo to Pictures", "Pantalla completa": "Full screen",
  "Conectando": "Connecting", "Conectando con la cámara…": "Connecting to the camera…",
  "Control": "Control", "Velocidad": "Speed", "Centrar": "Center",
  "Mantén pulsado o usa las flechas del teclado": "Hold to move, or use the arrow keys",
  "Posiciones": "Positions", "Pausado": "Paused", "Reconectando": "Reconnecting",
  "En vivo · fotos": "Live · snapshots", "Sin conexión con la cámara. Reintentando…": "No connection to the camera. Retrying…",
  "Foto guardada en Imágenes ▸ CamPanel": "Photo saved to Pictures ▸ CamPanel",
  "Vídeo limitado a fotos. Para vídeo fluido instala ffmpeg: brew install ffmpeg": "Video limited to snapshots. For smooth video install ffmpeg: brew install ffmpeg",
  "No se pudo iniciar ffmpeg": "Could not start ffmpeg",
  "Guardar posición actual": "Save current position", "Borrar posición": "Delete position",
  "Nueva posición": "New position", "Se guardará hacia donde apunta ahora la cámara.": "It will save where the camera is pointing now.",
  "Guardar": "Save", "Cancelar": "Cancel", "Aceptar": "OK", "Borrar": "Delete",
  "Posición guardada": "Position saved", "Posición borrada": "Position deleted",
  "¿Borrar «{name}»?": "Delete “{name}”?", "Yendo a «{name}»": "Going to “{name}”",
  "{n} guardada": "{n} saved", "{n} guardadas": "{n} saved",
  // red
  "Modo": "Mode", "Cómo obtiene la cámara su dirección": "How the camera gets its address",
  "Automático (DHCP)": "Automatic (DHCP)", "Manual": "Manual", "Máscara de subred": "Subnet mask",
  "Puerta de enlace": "Gateway", "DNS principal": "Primary DNS", "DNS secundario": "Secondary DNS",
  "Aplicar": "Apply", "Puertos": "Ports", "Web (HTTP)": "Web (HTTP)", "HTTPS": "HTTPS",
  "Medios / RTSP": "Media / RTSP", "ONVIF": "ONVIF",
  "¿Cambiar la dirección IP?": "Change the IP address?",
  "La cámara pedirá una dirección por DHCP y puede cambiar de IP.": "The camera will request an address via DHCP and its IP may change.",
  "La cámara pasará a {ip}. Si te equivocas, perderás el acceso hasta que la restablezcas.": "The camera will switch to {ip}. If you get it wrong, you will lose access until you reset it.",
  "Enviado. Si la IP cambió, vuelve a conectar con la nueva.": "Sent. If the IP changed, reconnect using the new one.",
  "¿Cambiar los puertos?": "Change the ports?",
  "Si cambias el puerto web tendrás que volver a conectar con el nuevo.": "If you change the web port you will have to reconnect using the new one.",
  "Puertos guardados. La cámara puede reiniciarse.": "Ports saved. The camera may restart.",
  // wifi
  "Estado": "Status", "Redes disponibles": "Available networks", "Buscar": "Scan", "Buscando…": "Scanning…",
  "Pulsa «Buscar» para listar las redes que ve la cámara.": "Press “Scan” to list the networks the camera can see.",
  "Conectar a una red": "Connect to a network", "Nombre (SSID)": "Name (SSID)", "Seguridad": "Security",
  "WPA / WPA2": "WPA / WPA2", "Abierta": "Open", "WEP": "WEP",
  "Activado": "Enabled", "Desactivado": "Disabled", "Sin conectar": "Not connected",
  "WiFi activado": "WiFi enabled", "Conexión": "Connection", "Red actual": "Current network",
  "La cámara no ve ninguna red.": "The camera cannot see any network.",
  "Falta el nombre de la red": "Network name is missing",
  "¿Conectar a «{ssid}»?": "Connect to “{ssid}”?",
  "Si la contraseña es incorrecta, la cámara podría quedar sin conexión inalámbrica.": "If the password is wrong, the camera may lose its wireless connection.",
  "Configuración WiFi enviada": "WiFi settings sent",
  // sistema
  "Dispositivo": "Device", "Nombre de la cámara": "Camera name", "Imagen": "Image",
  "Espejo horizontal": "Mirror", "Invierte la imagen de izquierda a derecha": "Flips the image left to right",
  "Voltear vertical": "Flip vertically", "Para cámaras montadas en el techo": "For ceiling-mounted cameras",
  "Infrarrojos": "Infrared", "Visión nocturna": "Night vision", "Auto": "Auto", "Encendidos": "On", "Apagados": "Off",
  "Reiniciar cámara": "Restart camera", "Tarda aproximadamente un minuto en volver": "Takes about a minute to come back",
  "Reiniciar": "Restart", "Nombre guardado": "Name saved",
  "Modelo": "Model", "Número de serie": "Serial number", "Dirección MAC": "MAC address",
  "Firmware": "Firmware", "Hardware": "Hardware",
  "¿Reiniciar la cámara?": "Restart the camera?",
  "Perderás el vídeo durante aproximadamente un minuto.": "You will lose the video for about a minute.",
  "Reiniciando… vuelve en un minuto.": "Restarting… back in a minute.",
  "Sí": "Yes", "No": "No",
  // errores de la cámara y de la app
  "Formato de orden incorrecto": "Invalid command format",
  "Usuario o contraseña incorrectos": "Wrong user or password",
  "Acceso denegado": "Access denied",
  "Esta cámara no admite esa orden": "This camera does not support that command",
  "Demasiados usuarios conectados": "Too many users connected",
  "La cámara respondió con el código {code}": "The camera answered with code {code}",
  "Error {code}": "Error {code}",
  "Faltan datos": "Missing data",
  "Solo se permiten direcciones de la red local": "Only local-network addresses are allowed",
  "No conectado": "Not connected", "Orden no permitida": "Command not allowed", "URL inválida": "Invalid URL",
  "Respuesta no válida de la cámara": "Invalid response from the camera",
  "La cámara no devolvió imagen": "The camera did not return an image", "No encontrado": "Not found",
  "No se pudo contactar con la cámara": "Could not reach the camera",
  "Credenciales guardadas rechazadas": "Saved credentials were rejected",
};

/* Mensajes del servidor Swift con datos variables */
const PATTERNS = [
  [/^No se pudo contactar con la cámara en (.+?)\. ?(.*)$/, (m) => `Could not reach the camera at ${m[1]}. ${m[2]}`.trim()],
  [/^La cámara rechazó el acceso \(código (.+)\)$/, (m) => `The camera refused access (code ${m[1]})`],
  [/^No se pudo guardar: (.*)$/, (m) => `Could not save: ${m[1]}`],
];

function fill(s, vars) { return vars ? s.replace(/\{(\w+)\}/g, (_, k) => (k in vars ? vars[k] : `{${k}}`)) : s; }

/* t("texto en español", {vars}) → texto en el idioma activo */
function t(es, vars) { return fill(LANG === "es" ? es : (EN[es] ?? es), vars); }

/* Traduce un mensaje de error recibido del servidor */
function tr(msg) {
  if (LANG === "es" || !msg) return msg;
  if (EN[msg]) return EN[msg];
  for (const [re, f] of PATTERNS) { const m = msg.match(re); if (m) return f(m); }
  return msg;
}

/* Traduce el HTML estático (texto, title, placeholder) */
function translateStatic(root = document.body) {
  if (LANG === "es") return;
  const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (w.nextNode()) nodes.push(w.currentNode);
  for (const n of nodes) {
    const k = n.nodeValue.trim();
    if (k && EN[k]) n.nodeValue = n.nodeValue.replace(k, EN[k]);
  }
  root.querySelectorAll("[title],[placeholder],[aria-label]").forEach((el) => {
    for (const a of ["title", "placeholder", "aria-label"]) {
      const v = el.getAttribute(a);
      if (v && EN[v]) el.setAttribute(a, EN[v]);
    }
  });
}
document.addEventListener("DOMContentLoaded", () => translateStatic());
