import SwiftUI
import AVFoundation
import UIKit

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

    private let keyField = "erome.key"
    private let expiryField = "erome.keyExpiry"
    private let rememberField = "erome.remember"

    private let bg = Color(red: 0.047, green: 0.047, blue: 0.063)
    private let card = Color(red: 0.071, green: 0.071, blue: 0.094)
    private let line = Color.white.opacity(0.07)
    private let accent = Color(red: 0.937, green: 0.298, blue: 0.541)
    private let green = Color(red: 0.373, green: 0.816, blue: 0.541)
    private let red = Color(red: 0.937, green: 0.42, blue: 0.42)
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
                    .foregroundColor(keyMsg.hasPrefix("Key activa") ? green : red)
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
        case "aim_head": return accent
        case "aim_cuello": return blue
        case "holo_armas": return violet
        case "holo_personajes": return teal
        default: return muted
        }
    }

    private func symbol(_ option: EroMeOption) -> String {
        switch option.id {
        case "aim_drag": return "hand.draw.fill"
        case "aim_head": return "target"
        case "aim_cuello": return "figure.arms.open"
        case "holo_armas": return "wand.and.stars"
        case "holo_personajes": return "person.crop.square.fill"
        default: return "square.fill"
        }
    }

    private func row(_ option: EroMeOption) -> some View {
        let on = engine.active.contains(option.id)
        let working = engine.busy == option.id
        let unavailable = engine.missing.contains(option.id)

        return Button {
            engine.toggle(option)
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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(green.opacity(0.85))
                Text("Compatible iOS 16.0 - 26.6")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())

            Button {
                openGame()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 13))
                    Text("Abrir Free Fire Max")
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

            Button {
                openContact()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                    Text("Contacto / Comprar")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(telegram)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(telegram.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(telegram.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
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

    private func openGame() {
        for candidate in ["freefiremax://", "freefire://"] {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        if let url = URL(string: "https://apps.apple.com/app/id1300146617") {
            UIApplication.shared.open(url)
        }
    }

    private func openContact() {
        if let url = URL(string: EroMeLink.contact) {
            UIApplication.shared.open(url)
        }
    }
}
