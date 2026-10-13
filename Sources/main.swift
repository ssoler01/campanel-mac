import Cocoa
import WebKit
import Security

// MARK: - Llavero

enum Vault {
    static let service = "io.github.ssoler01.campanel"
    static let account = "camera"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ values: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        delete()
        var q = base
        q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> [String: String]? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return obj
    }

    static func delete() { SecItemDelete(base as CFDictionary) }
}

// MARK: - Cámara

final class Camera {
    var host = "", user = "", pwd = ""
    var port = 88
    var connected: Bool { !host.isEmpty }

    func reset() { host = ""; user = ""; pwd = ""; port = 88 }

    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func url(_ path: String, _ params: [String: String]) -> URL? {
        var all = params
        all["usr"] = user
        all["pwd"] = pwd
        let q = all.map { "\(Camera.encode($0.key))=\(Camera.encode($0.value))" }.joined(separator: "&")
        return URL(string: "http://\(host):\(port)\(path)?\(q)")
    }

    /// Solo red local: IPv4 privada, loopback o nombres .local
    static func isLocal(_ host: String) -> Bool {
        if host.hasSuffix(".local") || host == "localhost" { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] == 10 || p[0] == 127 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }
}

extension Camera {
    /// Hosts de la red local según la máscara real de cada interfaz Ethernet/WiFi (en*).
    /// Se admiten redes hasta /22 (1022 equipos); si es mayor se explora el /24 del propio Mac.
    static func lanHosts() -> [String] {
        func dotted(_ v: UInt32) -> String { "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)" }
        var ranges = Set<[UInt32]>()
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, var ptr = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        while true {
            let ifa = ptr.pointee
            if let addr = ifa.ifa_addr, let mask = ifa.ifa_netmask,
               addr.pointee.sa_family == UInt8(AF_INET),
               (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               String(cString: ifa.ifa_name).hasPrefix("en") {
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                var m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                if isLocal(dotted(ip)) && !dotted(ip).hasPrefix("127.") {
                    if m < 0xFFFF_FC00 { m = 0xFFFF_FF00 }          // más grande que /22 → solo el /24
                    if m > 0xFFFF_FF00 { m = 0xFFFF_FF00 }          // más pequeña que /24 → /24 (cubre sobradamente)
                    let net = ip & m, bcast = net | ~m
                    ranges.insert([net + 1, bcast - 1])
                }
            }
            guard let next = ifa.ifa_next else { break }
            ptr = next
        }
        var seen = Set<UInt32>(), out: [String] = []
        for r in ranges.sorted(by: { $0[0] < $1[0] }) {
            for v in r[0]...r[1] where seen.insert(v).inserted { out.append(dotted(v)) }
        }
        return out
    }
}

/// Convierte <CGI_Result><a>1</a><b>2</b></CGI_Result> en [a: 1, b: 2]
final class FlatXML: NSObject, XMLParserDelegate {
    private var result: [String: String] = [:]
    private var key = "", text = "", depth = 0

    static func parse(_ data: Data) -> [String: String]? {
        let h = FlatXML()
        let p = XMLParser(data: data)
        p.delegate = h
        return p.parse() ? h.result : nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if depth == 2 { key = name; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if depth == 2 { text += string } }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if depth == 2, let s = String(data: data, encoding: .utf8) { text += s }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if depth == 2 { result[key] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        depth -= 1
    }
}

// MARK: - Esquema campanel:// (interfaz + puente a la cámara)

final class SchemeHandler: NSObject, WKURLSchemeHandler, URLSessionDataDelegate {
    let camera = Camera()
    private var live: [ObjectIdentifier: WKURLSchemeTask] = [:]
    private var streamTasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var streamOwner: [Int: WKURLSchemeTask] = [:]

    private lazy var api: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()
    private lazy var streamSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 24 * 3600
        return URLSession(configuration: c, delegate: self, delegateQueue: .main)
    }()

    private let webRoot = Bundle.main.resourceURL!.appendingPathComponent("web")

    // MARK: WKURLSchemeHandler

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        live[ObjectIdentifier(task as AnyObject)] = task
        guard let url = task.request.url else { return fail(task, "URL inválida") }
        let q = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") })

        switch url.path {
        case "/api/session": session(task)
        case "/api/login": login(task, q)
        case "/api/logout": camera.reset(); Vault.delete(); json(task, ["ok": true])
        case "/api/forget": Vault.delete(); json(task, ["ok": true])
        case "/api/cmd": command(task, q)
        case "/api/snap": snapshot(task, save: false)
        case "/api/savesnap": snapshot(task, save: true)
        case "/api/stream": stream(task)
        case "/api/scan": scan(task)
        default: staticFile(task, url.path)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        live[id] = nil
        streamTasks[id]?.cancel()
        streamTasks[id] = nil
    }

    // MARK: helpers de respuesta

    private func isLive(_ t: WKURLSchemeTask) -> Bool { live[ObjectIdentifier(t as AnyObject)] != nil }

    private func respond(_ t: WKURLSchemeTask, status: Int = 200, mime: String, data: Data) {
        guard isLive(t), let url = t.request.url else { return }
        let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": mime, "Cache-Control": "no-store",
                                               "Content-Length": String(data.count)])!
        t.didReceive(r)
        t.didReceive(data)
        t.didFinish()
        live[ObjectIdentifier(t as AnyObject)] = nil
    }

    private func json(_ t: WKURLSchemeTask, _ obj: [String: Any], status: Int = 200) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        respond(t, status: status, mime: "application/json; charset=utf-8", data: d)
    }

    private func fail(_ t: WKURLSchemeTask, _ message: String, status: Int = 502) {
        json(t, ["error": message], status: status)
    }

    // MARK: rutas

    private func session(_ t: WKURLSchemeTask) {
        if camera.connected {
            return deviceInfo { [self] info in
                json(t, ["connected": true, "host": camera.host, "port": camera.port,
                         "user": camera.user, "info": info ?? [:]])
            }
        }
        guard let saved = Vault.load(), let host = saved["host"], let user = saved["user"],
              let pwd = saved["pwd"], let port = Int(saved["port"] ?? "") else {
            return json(t, ["connected": false])
        }
        // Reconexión automática con lo guardado en el Llavero
        camera.host = host; camera.port = port; camera.user = user; camera.pwd = pwd
        deviceInfo { [self] info in
            if let info, info["result"] == "0" {
                json(t, ["connected": true, "host": host, "port": port, "user": user, "info": info])
            } else {
                camera.reset()
                json(t, ["connected": false, "saved": ["host": host, "port": port, "user": user],
                         "reason": info == nil ? "No se pudo contactar con la cámara" : "Credenciales guardadas rechazadas"])
            }
        }
    }

    private func login(_ t: WKURLSchemeTask, _ q: [String: String]) {
        let host = (q["host"] ?? "").trimmingCharacters(in: .whitespaces)
        let user = (q["user"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty, let port = Int(q["port"] ?? "") else {
            return fail(t, "Faltan datos", status: 400)
        }
        guard Camera.isLocal(host) else { return fail(t, "Solo se permiten direcciones de la red local", status: 400) }
        camera.host = host; camera.port = port; camera.user = user; camera.pwd = q["pwd"] ?? ""
        deviceInfo { [self] info in
            guard let info else {
                camera.reset()
                return fail(t, "No se pudo contactar con la cámara en \(host):\(port). \(lastError)")
            }
            guard info["result"] == "0" else {
                camera.reset()
                let msg = info["result"] == "-2" ? "Usuario o contraseña incorrectos" : "La cámara rechazó el acceso (código \(info["result"] ?? "?"))"
                return fail(t, msg, status: 401)
            }
            if q["remember"] == "1" {
                Vault.save(["host": host, "port": String(port), "user": user, "pwd": q["pwd"] ?? ""])
            }
            json(t, ["ok": true, "info": info])
        }
    }

    private var lastError = ""

    private func deviceInfo(_ done: @escaping ([String: String]?) -> Void) {
        guard let u = camera.url("/cgi-bin/CGIProxy.fcgi", ["cmd": "getDevInfo"]) else { return done(nil) }
        api.dataTask(with: u) { [self] data, _, error in
            DispatchQueue.main.async { [self] in
                if let e = error as NSError? { lastError = "\(e.localizedDescription) [\(e.domain) \(e.code)]" }
                done(data.flatMap(FlatXML.parse))
            }
        }.resume()
    }

    private static let allowed: Set<String> = [
        "getDevInfo", "getDevState", "getDevName", "setDevName",
        "getIPInfo", "setIpInfo", "getPortInfo", "setPortInfo",
        "getWifiConfig", "refreshWifiList", "getWifiList", "setWifiSetting",
        "ptzMoveUp", "ptzMoveDown", "ptzMoveLeft", "ptzMoveRight",
        "ptzMoveTopLeft", "ptzMoveTopRight", "ptzMoveBottomLeft", "ptzMoveBottomRight",
        "ptzStopRun", "ptzReset", "getPTZSpeed", "setPTZSpeed",
        "getPTZPresetPointList", "ptzAddPresetPoint", "ptzDeletePresetPoint", "ptzGotoPresetPoint",
        "getSystemTime", "rebootSystem",
        "getInfraLedConfig", "setInfraLedConfig", "openInfraLed", "closeInfraLed",
        "getMirrorAndFlipSetting", "mirrorVideo", "flipVideo",
    ]

    private func command(_ t: WKURLSchemeTask, _ q: [String: String]) {
        guard camera.connected else { return fail(t, "No conectado", status: 401) }
        guard let cmd = q["cmd"], Self.allowed.contains(cmd) else {
            return fail(t, "Orden no permitida", status: 400)
        }
        var params: [String: String] = ["cmd": cmd]
        if let p = q["p"], let d = p.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for (k, v) in o { params[k] = "\(v)" }
        }
        guard let u = camera.url("/cgi-bin/CGIProxy.fcgi", params) else { return fail(t, "URL inválida") }
        api.dataTask(with: u) { [self] data, _, error in
            DispatchQueue.main.async { [self] in
                if let error { return fail(t, error.localizedDescription) }
                guard let data, let r = FlatXML.parse(data) else { return fail(t, "Respuesta no válida de la cámara") }
                json(t, r)
            }
        }.resume()
    }

    private func snapshot(_ t: WKURLSchemeTask, save: Bool) {
        guard camera.connected else { return fail(t, "No conectado", status: 401) }
        guard let u = camera.url("/cgi-bin/CGIProxy.fcgi", ["cmd": "snapPicture2"]) else { return fail(t, "URL inválida") }
        api.dataTask(with: u) { [self] data, resp, error in
            DispatchQueue.main.async { [self] in
                let mime = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard error == nil, let data, mime.hasPrefix("image/") else {
                    return fail(t, error?.localizedDescription ?? "La cámara no devolvió imagen")
                }
                guard save else { return respond(t, mime: mime, data: data) }
                let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("CamPanel", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd-HHmmss"
                let file = dir.appendingPathComponent("CamPanel-\(f.string(from: Date())).jpg")
                do {
                    try data.write(to: file)
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    json(t, ["ok": true, "path": file.path])
                } catch { fail(t, "No se pudo guardar: \(error.localizedDescription)") }
            }
        }.resume()
    }

    /// Busca cámaras con API Foscam en la red local probando unos pocos puertos.
    private func scan(_ t: WKURLSchemeTask) {
        let hosts = Camera.lanHosts()
        let ports = [88, 89, 80, 8080]
        let targets = hosts.flatMap { h in ports.map { (h, $0) } }
        Task {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 1.0
            cfg.waitsForConnectivity = false
            let session = URLSession(configuration: cfg)

            @Sendable func probe(_ host: String, _ port: Int) async -> (String, Int)? {
                guard let url = URL(string: "http://\(host):\(port)/cgi-bin/CGIProxy.fcgi?cmd=getDevInfo&usr=&pwd=") else { return nil }
                guard let (data, _) = try? await session.data(from: url),
                      String(data: data.prefix(512), encoding: .utf8)?.contains("<CGI_Result>") == true else { return nil }
                return (host, port)
            }

            var found: [(String, Int)] = []
            await withTaskGroup(of: (String, Int)?.self) { group in
                var it = targets.makeIterator()
                for _ in 0..<120 {
                    guard let (h, p) = it.next() else { break }
                    group.addTask { await probe(h, p) }
                }
                for await r in group {
                    if let r { found.append(r) }
                    if let (h, p) = it.next() { group.addTask { await probe(h, p) } }
                }
            }
            func key(_ h: String) -> Int { h.split(separator: ".").reduce(0) { $0 * 256 + (Int($1) ?? 0) } }
            let sorted = found.sorted { (key($0.0), $0.1) < (key($1.0), $1.1) }
            DispatchQueue.main.async { [self] in
                json(t, ["cameras": sorted.map { ["host": $0.0, "port": $0.1] },
                         "scanned": hosts.count])
            }
        }
    }

    private func stream(_ t: WKURLSchemeTask) {
        guard camera.connected else { return fail(t, "No conectado", status: 401) }
        guard let u = camera.url("/cgi-bin/CGIStream.cgi", ["cmd": "GetMJPEGStream"]) else { return fail(t, "URL inválida") }
        let task = streamSession.dataTask(with: u)
        streamOwner[task.taskIdentifier] = t
        streamTasks[ObjectIdentifier(t as AnyObject)] = task
        task.resume()
    }

    private func staticFile(_ t: WKURLSchemeTask, _ path: String) {
        let rel = (path == "/" || path.isEmpty) ? "index.html" : String(path.dropFirst())
        let file = webRoot.appendingPathComponent(rel).standardizedFileURL
        guard file.path.hasPrefix(webRoot.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else { return fail(t, "No encontrado", status: 404) }
        let types = ["html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8",
                     "css": "text/css; charset=utf-8", "svg": "image/svg+xml", "png": "image/png"]
        respond(t, mime: types[file.pathExtension] ?? "application/octet-stream", data: data)
    }

    // MARK: URLSessionDataDelegate (vídeo MJPEG)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let t = streamOwner[dataTask.taskIdentifier], isLive(t), let url = t.request.url {
            let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let r = HTTPURLResponse(url: url, statusCode: ok ? 200 : 502, httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": mime, "Cache-Control": "no-store"])!
            t.didReceive(r)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let t = streamOwner[dataTask.taskIdentifier], isLive(t) { t.didReceive(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let t = streamOwner[task.taskIdentifier] else { return }
        streamOwner[task.taskIdentifier] = nil
        let id = ObjectIdentifier(t as AnyObject)
        streamTasks[id] = nil
        guard isLive(t) else { return }
        live[id] = nil
        if let error, (error as NSError).code != NSURLErrorCancelled { t.didFailWithError(error) } else { t.didFinish() }
    }
}

// MARK: - Ventana

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow!
    let handler = SchemeHandler()

    func applicationDidFinishLaunching(_ n: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(handler, forURLScheme: "campanel")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.allowsMagnification = false
        if #available(macOS 13.3, *) { web.isInspectable = true }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "CamPanel"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 920, height: 640)
        window.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.063, green: 0.071, blue: 0.086, alpha: 1)
                : NSColor(srgbRed: 0.949, green: 0.953, blue: 0.961, alpha: 1)
        }
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("CamPanelMain")
        window.makeKeyAndOrderFront(nil)

        web.load(URLRequest(url: URL(string: "campanel://app/index.html")!))
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Español si el idioma preferido del sistema es español; inglés en el resto.
    private let isSpanish = Locale.preferredLanguages.first?.lowercased().hasPrefix("es") ?? false
    private func L(_ es: String, _ en: String) -> String { isSpanish ? es : en }

    private func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let it = NSMenuItem(); main.addItem(it)
            let m = NSMenu(title: title); items.forEach { m.addItem($0) }; it.submenu = m
        }
        func item(_ t: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        add("CamPanel", [
            item(L("Acerca de CamPanel", "About CamPanel"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item(L("Ocultar CamPanel", "Hide CamPanel"), #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item(L("Salir de CamPanel", "Quit CamPanel"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        add(L("Edición", "Edit"), [
            item(L("Deshacer", "Undo"), Selector(("undo:")), "z"),
            item(L("Rehacer", "Redo"), Selector(("redo:")), "Z", [.command, .shift]),
            .separator(),
            item(L("Cortar", "Cut"), #selector(NSText.cut(_:)), "x"),
            item(L("Copiar", "Copy"), #selector(NSText.copy(_:)), "c"),
            item(L("Pegar", "Paste"), #selector(NSText.paste(_:)), "v"),
            item(L("Seleccionar todo", "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ])
        add(L("Visualización", "View"), [
            item(L("Pantalla completa", "Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        add(L("Ventana", "Window"), [
            item(L("Minimizar", "Minimize"), #selector(NSWindow.miniaturize(_:)), "m"),
            item(L("Cerrar", "Close"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
