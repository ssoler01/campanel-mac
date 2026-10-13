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
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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
            item("Acerca de CamPanel", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Ocultar CamPanel", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Salir de CamPanel", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Rehacer", Selector(("redo:")), "Z", [.command, .shift]),
            .separator(),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("Visualización", [
            item("Pantalla completa", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        add("Ventana", [
            item("Minimizar", #selector(NSWindow.miniaturize(_:)), "m"),
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
