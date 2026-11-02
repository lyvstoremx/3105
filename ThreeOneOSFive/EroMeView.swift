import SwiftUI
import AVFoundation
import UIKit
import CryptoKit

final class EroMeVoice: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play() {
        if start() { return }
        say("Levi activado")
    }

    private func start() -> Bool {
        let url = Bundle.main.url(forResource: "levi", withExtension: "mp3", subdirectory: "Patches")
            ?? Bundle.main.url(forResource: "levi", withExtension: "mp3")
        guard let url else { return false }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1
            player?.prepareToPlay()
            return player?.play() ?? false
        } catch {
            return false
        }
    }

    private func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = best()
        utterance.pitchMultiplier = 2.0
        utterance.rate = 0.4
        utterance.volume = 1
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }

    private func best() -> AVSpeechSynthesisVoice? {
        let spanish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }
        guard !spanish.isEmpty else { return nil }
        let enhanced = spanish.filter { $0.quality == .enhanced }
        return (enhanced.isEmpty ? spanish : enhanced).first
    }
}

private enum KeyNet {
    static let base = "https://erome-keys.lyvstoremxweb.workers.dev"

    static var hwid: String {
        let field = "erome.hwid"
        if let saved = UserDefaults.standard.string(forKey: field) { return saved }
        let made = UUID().uuidString
        UserDefaults.standard.set(made, forKey: field)
        return made
    }

    static func post(_ path: String, key: String, done: @escaping (Bool, Double?, String?) -> Void) {
        guard let url = URL(string: base + path) else {
            done(false, nil, "url")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key, "hwid": hwid])

        URLSession.shared.dataTask(with: req) { data, _, error in
            var ok = false
            var exp: Double?
            var msg: String?

            if let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                ok = obj["ok"] as? Bool ?? false
                if let n = obj["exp"] as? NSNumber { exp = n.doubleValue }
                msg = obj["error"] as? String
            } else if error != nil {
                msg = "sin conexion"
            }

            DispatchQueue.main.async { done(ok, exp, msg) }
        }.resume()
    }
}

struct EroMeView: View {
    @StateObject private var engine = EroMeEngine()
    @StateObject private var voice = EroMeVoice()

    @State private var showAdvanced = false
    @State private var key = ""
    @State private var expiry: Date?
    @State private var keyMsg: String?
    @State private var keyBusy = false
    @State private var remember = true
    @State private var now = Date()
    @State private var bypassOn = false
    @State private var opening = false

    private let keyField = "erome.key"
    private let expiryField = "erome.keyExpiry"
    private let rememberField = "erome.remember"

    private let bg = Color(red: 0.047, green: 0.047, blue: 0.063)
    private let card = Color(red: 0.071, green: 0.071, blue: 0.094)
    private let line = Color.white.opacity(0.07)
    private let accent = Color(red: 0.937, green: 0.298, blue: 0.541)
    private let green = Color(red: 0.373, green: 0.816, blue: 0.541)
    private let red = Color(red: 0.937, green: 0.42, blue: 0.42)
    private let amber = Color(red: 0.949, green: 0.678, blue: 0.267)
    private let muted = Color(red: 0.545, green: 0.545, blue: 0.588)
    private let telegram = Color(red: 0.259, green: 0.62, blue: 0.882)
    private let violet = Color(red: 0.545, green: 0.361, blue: 0.965)
    private let teal = Color(red: 0.235, green: 0.702, blue: 0.62)
    private let blue = Color(red: 0.298, green: 0.588, blue: 0.937)

    private var valid: Bool {
        guard let expiry else { return false }
        return expiry > now
    }

    private var loaded: Int { EroMeOption.all.count - engine.missing.count }
    private var activeCount: Int { engine.active.count }

    private var osVersion: (Int, Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion)
    }

    private var osText: String { "\(osVersion.0).\(osVersion.1)" }

    private var osState: Int {
        let (major, minor) = osVersion
        if major < 26 || major > 27 { return 2 }
        if major == 27 && minor > 0 { return 1 }
        return 0
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    keyCard
                    patchCard
                    footer
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadKey()
            engine.bootstrap()
            bypassOn = EroMeBypass.isActive()
            if valid { check() }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: engine.phase) { phase in
            if case .on = phase { voice.play() }
        }
        .fullScreenCover(isPresented: $showAdvanced) { ContentView() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                Image(systemName: "heart.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(spacing: 4) {
                Text("EroMe")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("External iOS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(muted)
                    .kerning(1.5)
            }

            HStack(spacing: 6) {
                Text(valid ? "KEY ACTIVA" : "SIN KEY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(valid ? green : red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((valid ? green : red).opacity(0.12))
                    .clipShape(Capsule())

                Text("\(loaded)/\(EroMeOption.all.count) parches")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())

                Text("\(activeCount) on")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(activeCount > 0 ? green : muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 3) {
            showAdvanced = true
        }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TU KEY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(muted)
                    .kerning(1)
                Spacer()
                if valid {
                    Text(remaining)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(green)
                }
            }

            HStack(spacing: 8) {
                TextField("EROME-XXXX-XXXX-XXXX", text: $key)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(line, lineWidth: 1)
                    )

                Button {
                    activate()
                } label: {
                    Group {
                        if keyBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Activar")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(width: 74, height: 40)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(keyBusy)
            }

            if let keyMsg {
                Text(keyMsg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(keyMsg.hasPrefix("Key activa") || keyMsg.hasPrefix("Bypass") ? green : red)
            }

            HStack(spacing: 8) {
                Button {
                    remember.toggle()
                    UserDefaults.standard.set(remember, forKey: rememberField)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: remember ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundColor(remember ? green : muted)
                        Text("Guardar key")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(muted)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if key.isEmpty {
                    Text("1 dispositivo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(muted)
                } else {
                    Button {
                        removeKey()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "key.slash.fill")
                                .font(.system(size: 10))
                            Text("Quitar key")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(line, lineWidth: 1)
        )
    }

    private var patchCard: some View {
        VStack(spacing: 10) {
            ForEach(EroMeOption.all.filter { $0.kind == .aimbot }) { option in
                row(option)
            }

            Rectangle()
                .fill(line)
                .frame(height: 1)
                .padding(.vertical, 2)

            ForEach(EroMeOption.all.filter { $0.kind == .hologram }) { option in
                row(option)
            }

            Rectangle()
                .fill(line)
                .frame(height: 1)
                .padding(.vertical, 2)

            ForEach(EroMeOption.all.filter { $0.kind == .extra }) { option in
                row(option)
            }
        }
        .padding(12)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(line, lineWidth: 1)
        )
    }

    private func tint(_ option: EroMeOption) -> Color {
        switch option.id {
        case "aim_drag": return violet
        case "aim_drag_antena": return violet
        case "aim_head": return accent
        case "aim_pecho": return blue
        case "holo_armas": return violet
        case "holo_personajes": return teal
        case "reset_guest": return amber
        default: return muted
        }
    }

    private func symbol(_ option: EroMeOption) -> String {
        switch option.id {
        case "aim_drag": return "hand.draw.fill"
        case "aim_drag_antena": return "antenna.radiowaves.left.and.right"
        case "aim_head": return "target"
        case "aim_pecho": return "figure.stand"
        case "holo_armas": return "wand.and.stars"
        case "holo_personajes": return "person.crop.square.fill"
        case "reset_guest": return "arrow.counterclockwise"
        default: return "square.fill"
        }
    }

    private func row(_ option: EroMeOption) -> some View {
        let on = engine.active.contains(option.id)
        let working = engine.busy == option.id
        let unavailable = engine.missing.contains(option.id)

        return Button {
            handle(option)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint(option).opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: symbol(option))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(tint(option))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(unavailable ? "sin parche" : (on ? "activo" : "apagado"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(muted)
                }

                Spacer()

                if working {
                    ProgressView().tint(accent)
                } else {
                    Text(on ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(on ? green : red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((on ? green : red).opacity(0.14))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke((on ? green : red).opacity(0.35), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.busy != nil || unavailable || !valid)
        .opacity(unavailable || !valid ? 0.45 : 1)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if valid {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Image(systemName: osState == 0 ? "checkmark.seal.fill" : (osState == 1 ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"))
                    .font(.system(size: 11))
                Text(osLabel)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(osState == 0 ? green.opacity(0.85) : (osState == 1 ? amber : red))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())

            Button {
                openGame()
            } label: {
                HStack(spacing: 8) {
                    if opening {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 13))
                    }
                    Text("Abrir Free Fire")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(opening)

            HStack(spacing: 8) {
                link("Canal oficial", icon: "megaphone.fill", color: telegram, url: EroMeLink.channel)
                link("Contacto", icon: "paperplane.fill", color: violet, url: EroMeLink.contact)
            }
        }
    }

    private func link(_ title: String, icon: String, color: Color, url: String) -> some View {
        Button {
            if let target = URL(string: url) { UIApplication.shared.open(target) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var osLabel: String {
        switch osState {
        case 1: return "iOS \(osText) sin verificar"
        case 2: return "Tu iOS \(osText) no es compatible"
        default: return "Compatible iOS 26.0 - 27.0 beta"
        }
    }

    private var statusText: String {
        switch engine.phase {
        case .idle: return "Listo"
        case .working(let t): return t
        case .on(let t): return "\(t) · activo"
        case .off(let t): return "\(t) · apagado, archivos restaurados"
        case .failed(let t): return t
        }
    }

    private var statusColor: Color {
        switch engine.phase {
        case .on: return green
        case .working: return accent
        case .failed: return red
        default: return muted
        }
    }

    private var remaining: String {
        guard let expiry else { return "" }
        let left = max(0, Int(expiry.timeIntervalSince(now)))
        let d = left / 86400
        let h = (left % 86400) / 3600
        let m = (left % 3600) / 60
        let s = left % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return String(format: "%02d:%02d", m, s)
    }

    private func loadKey() {
        remember = UserDefaults.standard.object(forKey: rememberField) as? Bool ?? true
        guard remember else { return }
        key = UserDefaults.standard.string(forKey: keyField) ?? ""
        if let stamp = UserDefaults.standard.object(forKey: expiryField) as? Date {
            expiry = stamp
        }
    }

    private func save(_ exp: Double?) {
        guard remember else { return }
        UserDefaults.standard.set(key, forKey: keyField)
        if let exp {
            let date = Date(timeIntervalSince1970: exp > 10_000_000_000 ? exp / 1000 : exp)
            UserDefaults.standard.set(date, forKey: expiryField)
            expiry = date
        }
    }

    private func removeKey() {
        key = ""
        expiry = nil
        keyMsg = nil
        UserDefaults.standard.removeObject(forKey: keyField)
        UserDefaults.standard.removeObject(forKey: expiryField)
    }

    private func activate() {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 6 else {
            keyMsg = "Escribe una key valida"
            return
        }
        key = clean
        keyBusy = true
        keyMsg = nil

        KeyNet.post("/claim", key: clean) { ok, exp, msg in
            keyBusy = false
            if ok {
                save(exp)
                keyMsg = "Key activa"
            } else {
                expiry = nil
                UserDefaults.standard.removeObject(forKey: expiryField)
                keyMsg = msg ?? "Key invalida"
            }
        }
    }

    private func check() {
        guard !key.isEmpty else { return }
        KeyNet.post("/check", key: key) { ok, exp, msg in
            if ok {
                save(exp)
            } else {
                expiry = nil
                keyMsg = msg ?? "Key vencida"
            }
        }
    }

    private func handle(_ option: EroMeOption) {
        let turningOn = !engine.active.contains(option.id)

        if option.id == "holo_armas", turningOn, !bypassOn {
            keyMsg = "Aplicando bypass…"
            DispatchQueue.global(qos: .userInitiated).async {
                let problem = EroMeBypass.apply()
                DispatchQueue.main.async {
                    guard problem == nil else {
                        keyMsg = problem
                        return
                    }
                    bypassOn = true
                    keyMsg = "Bypass activo"
                    engine.toggle(option)
                }
            }
            return
        }

        if !turningOn, bypassOn, option.kind == .hologram {
            let otroPrendido = EroMeOption.all.contains {
                $0.kind == .hologram && $0.id != option.id && engine.active.contains($0.id)
            }
            if !otroPrendido {
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = EroMeBypass.restore()
                    DispatchQueue.main.async {
                        bypassOn = false
                        engine.toggle(option)
                    }
                }
                return
            }
        }

        engine.toggle(option)
    }

    private func openGame() {
        guard engine.active.contains("holo_armas") || engine.active.contains("holo_personajes") else {
            launch()
            return
        }
        guard !bypassOn else {
            launch()
            return
        }
        opening = true
        keyMsg = "Aplicando bypass…"

        DispatchQueue.global(qos: .userInitiated).async {
            let problem = EroMeBypass.apply()
            DispatchQueue.main.async {
                opening = false
                guard problem == nil else {
                    keyMsg = problem
                    return
                }
                bypassOn = true
                keyMsg = "Bypass activo"
                launch()
            }
        }
    }

    private func launch() {
        for candidate in ["freefire://", "freefiremax://"] {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        if let url = URL(string: "https://apps.apple.com/app/id1300146617") {
            UIApplication.shared.open(url)
        }
    }
}

enum EroMeBypass {
    private static let bundle = "com.dts.freefireth"
    private static let marker = "EroMeExternal="
    private static let fakeSize = "70254592"
    private static let digest = "T86tZMfL7tWVGDqX8f5MB5yuEek="
    private static let size = "890282"

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("erome-bypass", isDirectory: true)
    }

    private static var backup: URL { directory.appendingPathComponent("fileinfo.original") }
    private static var pointer: URL { directory.appendingPathComponent("path.txt") }

    static func isActive() -> Bool {
        guard let info = storedPath(), let text = readText(info) else { return false }
        return text.contains(marker)
    }

    static func apply() -> String? {
        guard let container = ContainerStore.resolveAppContainerPath(bundleID: bundle) else {
            return "Free Fire no está instalado"
        }
        let handle = ContainerStore.grantContainerAccess(container)
        defer { if handle >= 0 { bad_query_release(handle) } }

        guard let info = locate(container) else { return "No se encontró el fileinfo" }
        guard let text = readText(info) else { return "No se pudo leer el fileinfo" }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(atPath: info, toPath: backup.path)
            try? info.write(to: pointer, atomically: true, encoding: .utf8)
        }

        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix("shaders,") }) else {
            return "El fileinfo no trae el renglón shaders"
        }
        lines[index] = "shaders," + marker + "," + fakeSize + ",3," + digest + "," + size + ",True,1,False,0"

        guard writeText(lines.joined(separator: "\n"), to: info) else { return "No se pudo escribir" }
        guard let check = readText(info), check.contains(marker) else {
            return "No se pudo verificar el cambio"
        }
        return nil
    }

    static func restore() -> String? {
        guard let info = storedPath(), FileManager.default.fileExists(atPath: backup.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: backup) else { return "Respaldo ilegible" }

        guard let container = ContainerStore.resolveAppContainerPath(bundleID: bundle) else {
            return "Free Fire no está instalado"
        }
        let handle = ContainerStore.grantContainerAccess(container)
        defer { if handle >= 0 { bad_query_release(handle) } }

        guard writeData(data, to: info) else { return "No se pudo restaurar" }
        try? FileManager.default.removeItem(at: backup)
        return nil
    }

    private static func storedPath() -> String? {
        guard let text = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func readText(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeText(_ text: String, to path: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return writeData(data, to: path)
    }

    private static func writeData(_ data: Data, to path: String) -> Bool {
        let target = URL(fileURLWithPath: path)
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".erome-" + UUID().uuidString)
        var attributes: [FileAttributeKey: Any] = [:]
        if let current = try? FileManager.default.attributesOfItem(atPath: path) {
            if let permissions = current[.posixPermissions] { attributes[.posixPermissions] = permissions }
            if let protection = current[.protectionKey] { attributes[.protectionKey] = protection }
        }
        guard FileManager.default.createFile(atPath: staging.path, contents: data, attributes: attributes) else {
            return false
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        if let handle = try? FileHandle(forWritingTo: staging) {
            try? handle.synchronize()
            try? handle.close()
        }
        return rename(staging.path, path) == 0
    }

    private static func locate(_ container: String) -> String? {
        let documents = (container as NSString).appendingPathComponent("Documents")
        let handle = ContainerStore.grantContainerAccess(documents)
        defer { if handle >= 0 { bad_query_release(handle) } }
        let found = search("fileinfo", under: documents, depth: 7)
        let ordered = found.sorted { first, second in
            let a = first.lowercased()
            let b = second.lowercased()
            let aOptional = a.contains("opcional") || a.contains("optional")
            let bOptional = b.contains("opcional") || b.contains("optional")
            return aOptional && !bOptional
        }
        return ordered.first
    }

    private static func search(_ name: String, under root: String, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        var found: [String] = []
        for item in items where item.lowercased() == name.lowercased() {
            found.append((root as NSString).appendingPathComponent(item))
        }
        for item in items {
            let full = (root as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            found += search(name, under: full, depth: depth - 1)
        }
        return found
    }
}
