"use strict";
const $ = (id) => document.getElementById(id);
const API = "campanel://app/api/";

/* ---------------- utilidades ---------------- */
const qs = (o) => Object.entries(o).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
const decode = (s) => { try { return decodeURIComponent(s); } catch { return s; } };

async function get(path, params = {}) {
  const r = await fetch(`${API}${path}?${qs(params)}`);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(tr(j.error) || t("Error {code}", { code: r.status }));
  return j;
}

const CGI_ERRORS = { "-1": "Formato de orden incorrecto", "-2": "Usuario o contraseña incorrectos",
  "-3": "Acceso denegado", "-4": "Esta cámara no admite esa orden", "-5": "Demasiados usuarios conectados" };
const cgiError = (code) => CGI_ERRORS[code] ? t(CGI_ERRORS[code]) : t("La cámara respondió con el código {code}", { code });

async function cmd(name, p = {}) {
  const d = await get("cmd", { cmd: name, p: JSON.stringify(p) });
  if (d.result !== undefined && d.result !== "0") {
    throw new Error(cgiError(d.result));
  }
  return d;
}

function toast(text, kind = "") {
  const t = document.createElement("div");
  t.className = "toast " + kind;
  t.textContent = text;
  $("toasts").append(t);
  setTimeout(() => t.remove(), kind === "err" ? 6000 : 3200);
}

async function run(fn, ok) {
  try { const r = await fn(); if (ok) toast(ok); return r; }
  catch (e) { toast(e.message, "err"); return undefined; }
}

function dialog({ title, body = "", ok = t("Aceptar"), danger = false, input = null }) {
  return new Promise((resolve) => {
    $("mTitle").textContent = title;
    $("mCancel").textContent = t("Cancelar");
    $("mBody").textContent = body;
    $("mBody").classList.toggle("hidden", !body);
    const inp = $("mInput");
    inp.classList.toggle("hidden", input === null);
    inp.value = input || "";
    const okBtn = $("mOk");
    okBtn.textContent = ok;
    okBtn.className = "btn " + (danger ? "danger solid" : "primary");
    $("modal").classList.remove("hidden");
    (input === null ? okBtn : inp).focus();
    const done = (v) => {
      $("modal").classList.add("hidden");
      okBtn.onclick = $("mCancel").onclick = inp.onkeydown = null;
      resolve(v);
    };
    okBtn.onclick = () => done(input === null ? true : inp.value.trim());
    $("mCancel").onclick = () => done(input === null ? false : null);
    inp.onkeydown = (e) => { if (e.key === "Enter") okBtn.click(); if (e.key === "Escape") done(null); };
  });
}

function seg(id, onPick) {
  const el = $(id);
  el.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    setSeg(id, b.dataset.v);
    onPick && onPick(b.dataset.v);
  });
}
const setSeg = (id, v) => $(id).querySelectorAll("button").forEach((b) => b.classList.toggle("on", b.dataset.v === String(v)));
const segValue = (id) => $(id).querySelector("button.on")?.dataset.v;

function kv(el, rows) {
  el.replaceChildren();
  for (const [k, v] of rows) {
    const a = document.createElement("div"); a.className = "k"; a.textContent = k;
    const b = document.createElement("div"); b.className = "v";
    if (v instanceof Node) b.append(v); else b.textContent = v;
    el.append(a, b);
  }
}
const badge = (yes, a = t("Sí"), b = t("No")) => {
  const s = document.createElement("span");
  s.className = "badge " + (yes ? "ok" : "no");
  s.textContent = yes ? a : b;
  return s;
};

/* ---------------- sesión ---------------- */
let session = null;

function enterApp(host, port, info) {
  session = { host, port };
  $("connect").classList.add("hidden");
  $("shell").classList.remove("hidden");
  $("camName").textContent = decode(info.devName || info.productName || t("Cámara"));
  $("camModel").textContent = info.productName || "";
  $("connAddr").textContent = `${host}:${port}`;
  setConn("ok");
  show("live");
}

function leaveApp() {
  stopVideo();
  session = null;
  $("shell").classList.add("hidden");
  $("connect").classList.remove("hidden");
  $("pwd").value = "";
  $("pwd").focus();
}

function setConn(state) {
  $("connDot").className = "dot" + (state === "ok" ? "" : state === "wait" ? " wait" : " off");
  $("connText").textContent = t({ ok: "Conectada", wait: "Reconectando…", off: "Sin conexión" }[state]);
}

$("loginForm").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const btn = $("loginBtn");
  btn.disabled = true; btn.textContent = t("Conectando…");
  $("loginError").textContent = "";
  try {
    const d = await get("login", {
      host: $("host").value, port: $("port").value, user: $("user").value,
      pwd: $("pwd").value, remember: $("remember").checked ? 1 : 0,
    });
    $("pwd").value = "";
    enterApp($("host").value.trim(), $("port").value, d.info);
  } catch (e) { $("loginError").textContent = e.message; }
  btn.disabled = false; btn.textContent = t("Conectar");
});

/* ---------------- búsqueda en la red ---------------- */
$("scanBtn").addEventListener("click", async () => {
  const btn = $("scanBtn"), box = $("scanResults");
  btn.disabled = true; btn.textContent = t("Buscando cámaras…");
  box.replaceChildren();
  try {
    const d = await get("scan");
    if (!d.scanned) {
      box.append(Object.assign(document.createElement("div"), { className: "msg", textContent: t("No se detectó ninguna red local. Comprueba que el Mac está conectado.") }));
    } else if (!d.cameras.length) {
      box.append(Object.assign(document.createElement("div"), { className: "msg", textContent: t("No se encontró ninguna cámara compatible. Comprueba que el Mac y la cámara están en la misma red.") }));
    } else {
      for (const c of d.cameras) {
        const b = document.createElement("button");
        b.type = "button"; b.className = "cam";
        const ip = document.createElement("b"); ip.textContent = c.host;
        const pt = document.createElement("span"); pt.textContent = t("puerto {port}", { port: c.port });
        b.append(ip, pt);
        b.onclick = () => { $("host").value = c.host; $("port").value = c.port; $("pwd").focus(); };
        box.append(b);
      }
      if (d.cameras.length === 1) {   // una sola: se rellena directamente
        $("host").value = d.cameras[0].host; $("port").value = d.cameras[0].port;
        $("pwd").focus();
      }
    }
  } catch (e) {
    box.append(Object.assign(document.createElement("div"), { className: "msg", textContent: e.message }));
  }
  btn.disabled = false; btn.textContent = t("Buscar cámaras en la red");
});

$("btnLogout").addEventListener("click", async () => {
  if (!await dialog({ title: t("¿Desconectar?"), body: t("Se borrarán las credenciales guardadas en el Llavero."), ok: t("Desconectar") })) return;
  await get("logout").catch(() => {});
  leaveApp();
});

/* ---------------- navegación ---------------- */
const loaders = { network: loadNetwork, wifi: loadWifi, system: loadSystem };
function show(page) {
  document.querySelectorAll("#nav button").forEach((b) => b.classList.toggle("on", b.dataset.page === page));
  document.querySelectorAll(".page").forEach((p) => p.classList.toggle("hidden", p.dataset.page !== page));
  if (page === "live") { startVideo(); loadPresets(); } else stopVideo();
  if (loaders[page]) run(loaders[page]);
}
$("nav").addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) show(b.dataset.page); });

/* ---------------- vídeo ---------------- */
let vAbort = null, vToken = 0, lastUrl = null, frames = 0, fpsTimer = null;

function setLive(on, label) {
  $("livePill").classList.toggle("on", on);
  $("liveLabel").textContent = t(label);
}
function veil(text) {
  $("veil").classList.toggle("gone", !text);
  if (text) $("veilText").textContent = t(text);
}
function paint(bytes) {
  const url = URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" }));
  const img = $("cam");
  img.src = url;
  if (lastUrl) URL.revokeObjectURL(lastUrl);
  lastUrl = url;
  frames++;
}

function indexOfPair(buf, a, b, from) {
  for (let i = from; i < buf.length - 1; i++) if (buf[i] === a && buf[i + 1] === b) return i;
  return -1;
}

async function readStream(token, signal) {
  const r = await fetch(`${API}stream?t=${Date.now()}`, { signal });
  if (!r.ok || !r.body) throw new Error("Sin flujo MJPEG");
  const reader = r.body.getReader();
  let buf = new Uint8Array(0), gotFrame = false;
  while (token === vToken) {
    const { value, done } = await reader.read();
    if (done) throw new Error("Flujo cerrado");
    const next = new Uint8Array(buf.length + value.length);
    next.set(buf); next.set(value, buf.length);
    buf = next;
    let latest = null;
    for (;;) {
      const s = indexOfPair(buf, 0xff, 0xd8, 0);
      if (s < 0) { buf = buf.subarray(Math.max(0, buf.length - 1)); break; }
      const e = indexOfPair(buf, 0xff, 0xd9, s + 2);
      if (e < 0) { buf = buf.subarray(s); break; }
      latest = buf.slice(s, e + 2);
      buf = buf.subarray(e + 2);
    }
    if (buf.length > 6e6) buf = new Uint8Array(0);
    if (latest) {
      paint(latest);
      if (!gotFrame) { gotFrame = true; veil(null); setLive(true, "En vivo"); setConn("ok"); }
    }
  }
}

async function pollSnapshots(token) {
  setLive(true, "En vivo · fotos");
  while (token === vToken) {
    const t0 = performance.now();
    const r = await fetch(`${API}snap?t=${Date.now()}`);
    if (!r.ok) throw new Error("Sin imagen");
    paint(await r.blob());
    veil(null); setConn("ok");
    await new Promise((res) => setTimeout(res, Math.max(0, 250 - (performance.now() - t0))));
  }
}

async function startVideo() {
  stopVideo();
  const token = ++vToken;
  vAbort = new AbortController();
  veil("Conectando con la cámara…");
  setLive(false, "Conectando");
  fpsTimer = setInterval(() => {
    const img = $("cam");
    $("hudMeta").textContent = img.naturalWidth ? `${img.naturalWidth}×${img.naturalHeight} · ${frames} fps` : "";
    frames = 0;
  }, 1000);
  let failures = 0;
  while (token === vToken) {
    try {
      try { await readStream(token, vAbort.signal); }
      catch (e) { if (token !== vToken) return; await pollSnapshots(token); }
    } catch (e) {
      if (token !== vToken) return;
      failures++;
      setLive(false, "Reconectando"); setConn("wait");
      veil(failures > 2 ? "Sin conexión con la cámara. Reintentando…" : "Reconectando…");
      if (failures > 2) setConn("off");
      await new Promise((res) => setTimeout(res, Math.min(8000, 1000 * failures)));
    }
  }
}

function stopVideo() {
  vToken++;
  vAbort?.abort();
  vAbort = null;
  clearInterval(fpsTimer);
  setLive(false, "Pausado");
}

$("btnFull").addEventListener("click", () => {
  if (document.fullscreenElement) document.exitFullscreen();
  else $("stage").requestFullscreen?.();
});
$("btnSnap").addEventListener("click", () => run(() => get("savesnap"), t("Foto guardada en Imágenes ▸ CamPanel")));

/* ---------------- PTZ ---------------- */
const NS = "http://www.w3.org/2000/svg";
const DIRS = [ // ángulo en grados (0 = derecha, sentido horario)
  ["Right", 0], ["BottomRight", 45], ["Bottom", 90], ["BottomLeft", 135],
  ["Left", 180], ["TopLeft", 225], ["Up", 270], ["TopRight", 315],
];
const CMD_OF = { Right: "ptzMoveRight", BottomRight: "ptzMoveBottomRight", Bottom: "ptzMoveDown",
  BottomLeft: "ptzMoveBottomLeft", Left: "ptzMoveLeft", TopLeft: "ptzMoveTopLeft", Up: "ptzMoveUp", TopRight: "ptzMoveTopRight" };

(function buildJoystick() {
  const svg = $("joy");
  const pt = (r, a) => [r * Math.cos(a * Math.PI / 180), r * Math.sin(a * Math.PI / 180)];
  const R1 = 34, R2 = 96, gap = 1.6;
  for (const [name, ang] of DIRS) {
    const [a0, a1] = [ang - 22.5 + gap, ang + 22.5 - gap];
    const [x1, y1] = pt(R1, a0), [x2, y2] = pt(R2, a0), [x3, y3] = pt(R2, a1), [x4, y4] = pt(R1, a1);
    const w = document.createElementNS(NS, "path");
    w.setAttribute("class", "wedge");
    w.setAttribute("d", `M${x1},${y1}L${x2},${y2}A${R2},${R2} 0 0 1 ${x3},${y3}L${x4},${y4}A${R1},${R1} 0 0 0 ${x1},${y1}Z`);
    w.dataset.dir = name;
    const [cx, cy] = pt(68, ang);
    const arrow = document.createElementNS(NS, "path");
    arrow.setAttribute("class", "arrow");
    arrow.setAttribute("fill", "none");
    arrow.setAttribute("stroke-linecap", "round");
    arrow.setAttribute("stroke-linejoin", "round");
    arrow.setAttribute("d", "M-5,3L0,-3L5,3");
    arrow.setAttribute("transform", `translate(${cx},${cy}) rotate(${ang + 90})`);
    svg.append(w, arrow);
    arrow.dataset.dir = name;
  }
  const home = document.createElementNS(NS, "circle");
  home.setAttribute("class", "home"); home.setAttribute("r", 26); home.setAttribute("stroke-width", 1);
  const ic = document.createElementNS(NS, "path");
  ic.setAttribute("class", "home-ic"); ic.setAttribute("fill", "none");
  ic.setAttribute("stroke-width", 2); ic.setAttribute("stroke-linecap", "round"); ic.setAttribute("stroke-linejoin", "round");
  ic.setAttribute("d", "M-9,1L0,-8L9,1M-6,-1V8H6V-1");
  home.addEventListener("click", () => run(() => cmd("ptzReset")));
  svg.append(home, ic);
})();

let ptzActive = null;
const wedgeOf = (d) => $("joy").querySelector(`.wedge[data-dir="${d}"]`);
async function ptzStart(dir) {
  if (ptzActive === dir) return;
  ptzActive = dir;
  wedgeOf(dir)?.classList.add("active");
  run(() => cmd(CMD_OF[dir]));
}
async function ptzStop() {
  if (!ptzActive) return;
  wedgeOf(ptzActive)?.classList.remove("active");
  ptzActive = null;
  run(() => cmd("ptzStopRun"));
}
$("joy").addEventListener("pointerdown", (e) => {
  const d = e.target.dataset?.dir;
  if (!d) return;
  e.target.setPointerCapture?.(e.pointerId);
  ptzStart(d);
});
["pointerup", "pointercancel", "lostpointercapture"].forEach((ev) => $("joy").addEventListener(ev, ptzStop));
window.addEventListener("blur", ptzStop);

const KEYS = { ArrowUp: "Up", ArrowDown: "Bottom", ArrowLeft: "Left", ArrowRight: "Right" };
document.addEventListener("keydown", (e) => {
  if (e.repeat || !KEYS[e.key] || $("shell").classList.contains("hidden")) return;
  if (document.querySelector(".page:not(.hidden)")?.dataset.page !== "live") return;
  if (["INPUT", "SELECT"].includes(document.activeElement?.tagName) || !$("modal").classList.contains("hidden")) return;
  e.preventDefault();
  ptzStart(KEYS[e.key]);
});
document.addEventListener("keyup", (e) => { if (KEYS[e.key]) ptzStop(); });

seg("speedSeg", (v) => run(() => cmd("setPTZSpeed", { speed: v })));

/* ---------------- posiciones ---------------- */
const thumbKey = (n) => `thumb:${n}`;
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch {} },
  del: (k) => { try { localStorage.removeItem(k); } catch {} },
};

async function snapThumb() {
  try {
    const blob = await (await fetch(`${API}snap?t=${Date.now()}`)).blob();
    const bmp = await createImageBitmap(blob);
    const c = document.createElement("canvas");
    c.width = 320; c.height = Math.round(320 * bmp.height / bmp.width);
    c.getContext("2d").drawImage(bmp, 0, 0, c.width, c.height);
    return c.toDataURL("image/jpeg", 0.7);
  } catch { return null; }
}

async function loadPresets() {
  const box = $("presets");
  const d = await run(() => cmd("getPTZPresetPointList"));
  if (!d) return;
  box.replaceChildren();
  const n = parseInt(d.cnt || "0", 10);
  let shown = 0;
  for (let i = 0; i < n; i++) {
    const name = decode(d[`point${i}`] || "");
    if (!name) continue;
    shown++;
    const card = document.createElement("div");
    card.className = "preset";
    const th = document.createElement("div");
    th.className = "thumb";
    const img = store.get(thumbKey(name));
    if (img) th.style.backgroundImage = `url(${img})`;
    else th.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>';
    const nm = document.createElement("div");
    nm.className = "name"; nm.textContent = name;
    const del = document.createElement("button");
    del.className = "del"; del.textContent = "✕"; del.title = t("Borrar posición");
    del.onclick = async (ev) => {
      ev.stopPropagation();
      if (!await dialog({ title: t("¿Borrar «{name}»?", { name }), ok: t("Borrar"), danger: true })) return;
      await run(() => cmd("ptzDeletePresetPoint", { name }), t("Posición borrada"));
      store.del(thumbKey(name));
      loadPresets();
    };
    card.onclick = () => run(() => cmd("ptzGotoPresetPoint", { name }), t("Yendo a «{name}»", { name }));
    card.append(th, nm, del);
    box.append(card);
  }
  const add = document.createElement("div");
  add.className = "preset add";
  add.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg><span>' + t("Guardar posición actual") + '</span>';
  add.onclick = async () => {
    const name = await dialog({ title: t("Nueva posición"), body: t("Se guardará hacia donde apunta ahora la cámara."), ok: t("Guardar"), input: "" });
    if (!name) return;
    const thumb = await snapThumb();
    const r = await run(() => cmd("ptzAddPresetPoint", { name }), t("Posición guardada"));
    if (r && thumb) store.set(thumbKey(name), thumb);
    loadPresets();
  };
  box.append(add);
  $("presetCount").textContent = shown ? t(shown > 1 ? "{n} guardadas" : "{n} guardada", { n: shown }) : "";
}

/* ---------------- red ---------------- */
function syncIpFields() {
  const auto = segValue("ipMode") === "1";
  for (const k of ["ip", "mask", "gate", "dns1", "dns2"]) $(k).disabled = auto;
}
seg("ipMode", syncIpFields);

async function loadNetwork() {
  const ip = await cmd("getIPInfo");
  setSeg("ipMode", ip.isDHCP === "1" ? "1" : "0");
  for (const k of ["ip", "mask", "gate", "dns1", "dns2"]) $(k).value = ip[k] || "";
  syncIpFields();
  const p = await cmd("getPortInfo");
  for (const k of ["webPort", "httpsPort", "mediaPort", "onvifPort"]) $(k).value = p[k] || "";
}

$("saveIp").addEventListener("click", async () => {
  const auto = segValue("ipMode") === "1";
  const ok = await dialog({
    title: t("¿Cambiar la dirección IP?"),
    body: auto ? t("La cámara pedirá una dirección por DHCP y puede cambiar de IP.")
                : t("La cámara pasará a {ip}. Si te equivocas, perderás el acceso hasta que la restablezcas.", { ip: $("ip").value }),
    ok: t("Aplicar"), danger: true,
  });
  if (!ok) return;
  await run(() => cmd("setIpInfo", {
    isDHCP: auto ? 1 : 0, ip: $("ip").value, mask: $("mask").value,
    gate: $("gate").value, dns1: $("dns1").value, dns2: $("dns2").value,
  }), t("Enviado. Si la IP cambió, vuelve a conectar con la nueva."));
});

$("savePorts").addEventListener("click", async () => {
  if (!await dialog({ title: t("¿Cambiar los puertos?"), body: t("Si cambias el puerto web tendrás que volver a conectar con el nuevo."), ok: t("Aplicar"), danger: true })) return;
  await run(() => cmd("setPortInfo", {
    webPort: $("webPort").value, httpsPort: $("httpsPort").value,
    mediaPort: $("mediaPort").value, onvifPort: $("onvifPort").value,
  }), t("Puertos guardados. La cámara puede reiniciarse."));
});

/* ---------------- wifi ---------------- */
async function loadWifi() {
  const w = await cmd("getWifiConfig");
  kv($("wifiState"), [
    [t("WiFi"), badge(w.isEnable === "1", t("Activado"), t("Desactivado"))],
    [t("Conexión"), badge(w.isConnected === "1", t("Conectada"), t("Sin conectar"))],
    [t("Red actual"), decode(w.ssid || w.connectedAP || "—")],
  ]);
  if (!$("ssid").value) $("ssid").value = decode(w.ssid || "");
}

function bars(q) {
  const n = Number(q);
  const lvl = Number.isFinite(n) ? Math.min(4, Math.max(1, Math.ceil(n / 25))) : 2;
  const el = document.createElement("span");
  el.className = "bars";
  for (let i = 1; i <= 4; i++) { const b = document.createElement("i"); if (i <= lvl) b.className = "f"; el.append(b); }
  return el;
}

$("scanWifi").addEventListener("click", () => run(async () => {
  const btn = $("scanWifi");
  btn.disabled = true; btn.textContent = t("Buscando…");
  try {
    await cmd("refreshWifiList");
    await new Promise((r) => setTimeout(r, 3000));
    const d = await cmd("getWifiList");
    const list = $("wifiList");
    list.replaceChildren();
    const n = parseInt(d.curCnt || d.totalCnt || "0", 10);
    for (let i = 0; i < n; i++) {
      const raw = d[`ap${i}`];
      if (!raw) continue;
      const parts = raw.split("+"); // ssid + bssid + calidad + seguridad
      const row = document.createElement("div");
      row.className = "net";
      const name = document.createElement("b");
      name.textContent = decode(parts[0]);
      row.append(bars(parts[2]), name);
      row.onclick = () => { $("ssid").value = decode(parts[0]); $("wpsk").focus(); };
      list.append(row);
    }
    if (!list.children.length) {
      const em = document.createElement("div");
      em.className = "empty";
      em.textContent = t("La cámara no ve ninguna red.");
      list.append(em);
    }
  } finally { btn.disabled = false; btn.textContent = t("Buscar"); }
}));

$("saveWifi").addEventListener("click", async () => {
  const ssid = $("ssid").value.trim();
  if (!ssid) return toast(t("Falta el nombre de la red"), "err");
  if (!await dialog({ title: t("¿Conectar a «{ssid}»?", { ssid }), body: t("Si la contraseña es incorrecta, la cámara podría quedar sin conexión inalámbrica."), ok: t("Conectar"), danger: true })) return;
  await run(() => cmd("setWifiSetting", {
    isEnable: 1, isUseWifi: 1, ssid, netType: 0, encryptType: $("wenc").value, psk: $("wpsk").value,
    authMode: 0, keyFormat: 0, defaultKey: 1, key1: "", key2: "", key3: "", key4: "",
    key1Len: 64, key2Len: 64, key3Len: 64, key4Len: 64,
  }), t("Configuración WiFi enviada"));
  $("wpsk").value = "";
});

/* ---------------- sistema ---------------- */
async function loadSystem() {
  const i = await cmd("getDevInfo");
  const labels = [["Modelo", "productName"], ["Número de serie", "serialNo"], ["Dirección MAC", "mac"],
                  ["Firmware", "firmwareVer"], ["Hardware", "hardwareVer"]];
  kv($("devInfo"), labels.filter(([, k]) => i[k]).map(([l, k]) => [t(l), decode(i[k])]));
  $("devName").value = decode(i.devName || "");
  const mf = await cmd("getMirrorAndFlipSetting").catch(() => null);
  if (mf) { $("mirror").checked = mf.isMirror === "1"; $("flip").checked = mf.isFlip === "1"; }
  const ir = await cmd("getInfraLedConfig").catch(() => null);
  if (ir) setSeg("irSeg", ir.mode === "0" ? "auto" : "on");
}

$("saveName").addEventListener("click", async () => {
  const name = $("devName").value.trim();
  if (!name) return;
  const r = await run(() => cmd("setDevName", { devName: name }), t("Nombre guardado"));
  if (r) $("camName").textContent = name;
});
$("mirror").addEventListener("change", () => run(() => cmd("mirrorVideo", { isMirror: $("mirror").checked ? 1 : 0 })));
$("flip").addEventListener("change", () => run(() => cmd("flipVideo", { isFlip: $("flip").checked ? 1 : 0 })));
seg("irSeg", (v) => run(async () => {
  if (v === "auto") return cmd("setInfraLedConfig", { mode: 0 });
  await cmd("setInfraLedConfig", { mode: 1 });
  return cmd(v === "on" ? "openInfraLed" : "closeInfraLed");
}));
$("reboot").addEventListener("click", async () => {
  if (!await dialog({ title: t("¿Reiniciar la cámara?"), body: t("Perderás el vídeo durante aproximadamente un minuto."), ok: t("Reiniciar"), danger: true })) return;
  await run(() => cmd("rebootSystem"), t("Reiniciando… vuelve en un minuto."));
});

/* ---------------- arranque ---------------- */
(async function boot() {
  try {
    const s = await get("session");
    if (s.connected) return enterApp(s.host, s.port, s.info || {});
    if (s.saved) {
      $("host").value = s.saved.host; $("port").value = s.saved.port; $("user").value = s.saved.user;
      if (s.reason) $("loginError").textContent = tr(s.reason);
    }
  } catch {}
  $("pwd").focus();
})();
