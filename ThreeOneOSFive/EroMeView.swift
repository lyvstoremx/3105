import SwiftUI
import AVFoundation
import UIKit

final class EroMeVoice {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func say(_ text: String) {
        if playClip() { return }
        speak(text)
    }

    private func playClip() -> Bool {
        guard let url = Bundle.main.url(
            forResource: "levi",
            withExtension: "mp3",
            subdirectory: "Patches"
        ) else { return false }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1
            player?.prepareToPlay()
            return player?.play() ?? false
        } catch {
            return false
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = best()
        utterance.pitchMultiplier = 2.0
        utterance.rate = 0.4
        utterance.volume = 1
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }

    private func best() -> AVSpeechSynthesisVoice? {
        let spanish = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
        guard !spanish.isEmpty else { return nil }
        let enhanced = spanish.filter { $0.quality == .enhanced }
        return (enhanced.isEmpty ? spanish : enhanced).first
    }
}

final class EroMeKey: ObservableObject {
    @Published private(set) var key: String = ""
    @Published private(set) var expiry: Date?
    @Published var remember: Bool {
        didSet { UserDefaults.standard.set(remember, forKey: rememberField) }
    }

    private let keyField = "erome.key"
    private let expiryField = "erome.keyExpiry"
    private let rememberField = "erome.remember"
    private let defaultDays: Double = 30

    init() {
        key = UserDefaults.standard.string(forKey: keyField) ?? ""
        if let stamp = UserDefaults.standard.object(forKey: expiryField) as? Date {
            expiry = stamp
        }
        remember = UserDefaults.standard.object(forKey: rememberField) as? Bool ?? true
    }

    var isValid: Bool {
        guard let expiry else { return false }
        return expiry > Date()
    }

    func save(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 8 else { return }
        key = clean
        expiry = Date().addingTimeInterval(defaultDays * 86_400)
        UserDefaults.standard.set(clean, forKey: keyField)
        UserDefaults.standard.set(expiry, forKey: expiryField)
    }

    func clear() {
        key = ""
        expiry = nil
        UserDefaults.standard.removeObject(forKey: keyField)
        UserDefaults.standard.removeObject(forKey: expiryField)
    }

    func remaining(from now: Date) -> String {
        guard let expiry else { return "sin key" }
        let seconds = Int(expiry.timeIntervalSince(now))
        if seconds <= 0 { return "vencida" }
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3_600
        let m = (seconds % 3_600) / 60
        let s = seconds % 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        return "\(m)m \(s)s"
    }
}

struct EroMeView: View {
    @StateObject private var engine = EroMeEngine()
    @StateObject private var keyStore = EroMeKey()
    @State private var keyInput = ""
    @State private var showAdvanced = false
    private let voice = EroMeVoice()

    private let bg = Color(red: 0.055, green: 0.043, blue: 0.063)
    private let card = Color(red: 0.094, green: 0.082, blue: 0.102)
    private let inner = Color(red: 0.129, green: 0.114, blue: 0.137)
    private let line = Color(red: 0.180, green: 0.161, blue: 0.192)
    private let accent = Color(red: 0.910, green: 0.376, blue: 0.557)
    private let green = Color(red: 0.310, green: 0.812, blue: 0.478)
    private let red = Color(red: 0.910, green: 0.361, blue: 0.361)
    private let muted = Color(red: 0.545, green: 0.514, blue: 0.576)

    private var loaded: Int { EroMeOption.all.count - engine.missing.count }
    private var activeCount: Int { engine.active.count }
    private var locked: Bool { !keyStore.isValid }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    heroCard
                    patchesCard
                    keyCard
                    openGameCard
                    sessionCard
                    footer
                }
                .padding(14)
            }
        }
        .onAppear { engine.bootstrap() }
        .onChange(of: engine.phase) { phase in
            if case .on = phase { voice.say("Levi activado") }
        }
        .fullScreenCover(isPresented: $showAdvanced) {
            ContentView().environmentObject(AppState())
        }
    }

    private var heroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.22))
                    .frame(width: 58, height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.5), lineWidth: 1))
                Image(systemName: "heart.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("EroMe")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                Text("\(loaded) de \(EroMeOption.all.count) módulos listos")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                Text(keyStore.isValid ? "ACCESO ACTIVO" : "ACCESO BLOQUEADO")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(keyStore.isValid ? green : red)
            }
            Spacer()
        }
        .padding(12)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))
        .onLongPressGesture(minimumDuration: 3.0) { showAdvanced = true }
    }

    private var patchesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parches visuales")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Aimbots y hologramas")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                }
                Spacer()
                Text("\(activeCount)/\(EroMeOption.all.count) ACTIVOS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(activeCount > 0 ? accent : muted)
            }

            sectionLabel("Aimbots", "uno a la vez")
            ForEach(EroMeOption.all.filter { $0.kind == .aimbot }) { row($0) }

            sectionLabel("Hologramas", "independientes")
            ForEach(EroMeOption.all.filter { $0.kind == .hologram }) { row($0) }

            if loaded == 0 {
                Text("Todavía no hay parches cargados. Los switches se activan cuando estén.")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))
    }

    private func sectionLabel(_ title: String, _ tag: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
            Spacer()
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(muted.opacity(0.7))
        }
        .padding(.top, 2)
    }

    private func subtitle(_ option: EroMeOption) -> String {
        switch option.id {
        case "aim_drag": return "Arrastre"
        case "aim_head": return "Cabeza"
        case "aim_cuello": return "Cuello"
        case "holo_armas": return "Armas"
        default: return "Personajes"
        }
    }

    private func symbol(_ option: EroMeOption) -> String {
        switch option.id {
        case "aim_drag": return "arrow.up.left.and.arrow.down.right"
        case "aim_head": return "scope"
        case "aim_cuello": return "figure.stand"
        case "holo_armas": return "cube"
        default: return "person.crop.square"
        }
    }

    private func tint(_ option: EroMeOption) -> Color {
        switch option.id {
        case "aim_drag": return accent
        case "aim_head": return Color(red: 0.63, green: 0.45, blue: 0.95)
        case "aim_cuello": return Color(red: 0.35, green: 0.75, blue: 0.72)
        case "holo_armas": return Color(red: 0.42, green: 0.60, blue: 0.95)
        default: return Color(red: 0.95, green: 0.55, blue: 0.45)
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint(option).opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: symbol(option))
                        .font(.system(size: 15))
                        .foregroundStyle(tint(option))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text(unavailable ? "sin parche" : subtitle(option))
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                }
                Spacer()
                Text(working ? "···" : (on ? "ON" : "OFF"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(on ? green : red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((on ? green : red).opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke((on ? green : red).opacity(0.55), lineWidth: 1))
            }
            .padding(9)
            .background(inner, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(engine.busy != nil || unavailable || locked)
        .opacity(unavailable || locked ? 0.5 : 1)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(keyStore.isValid ? green : red)
                    .frame(width: 8, height: 8)
                Text(keyStore.isValid ? "ACCESO ACTIVO" : "SIN ACCESO")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(keyStore.isValid ? green : red)
                Spacer()
                if keyStore.isValid {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(keyStore.remaining(from: context.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(green)
                    }
                }
            }

            if keyStore.isValid, let expiry = keyStore.expiry {
                Text("Acceso hasta \(formatted(expiry))")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }

            if keyStore.key.isEmpty || !keyStore.isValid {
                TextField("EROME-XXXX-XXXX-XXXX", text: $keyInput)
                    .font(.system(size: 12, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(inner, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)

                Button {
                    keyStore.save(keyInput)
                    keyInput = ""
                } label: {
                    Text("Activar key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(accent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                Text("Recordar key")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("", isOn: $keyStore.remember)
                    .labelsHidden()
                    .tint(accent)
                if !keyStore.key.isEmpty {
                    Button("Quitar") { keyStore.clear() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(red)
                }
            }

            Text("Dispositivos permitidos: 1 · iOS 26.0 – 26.6.1 y 27 beta")
                .font(.system(size: 10))
                .foregroundStyle(muted.opacity(0.8))
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke((keyStore.isValid ? green : line).opacity(0.6), lineWidth: 1)
        )
    }

    private var openGameCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                Text("ABRIR JUEGO")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
            }
            Button {
                openGame()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: locked ? "lock.fill" : "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(locked ? muted : accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Free Fire")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(locked ? muted : .white)
                        Text(locked ? "Activa el acceso para abrir" : "Cierra el juego antes de aplicar")
                            .font(.system(size: 10))
                            .foregroundStyle(muted)
                    }
                    Spacer()
                }
                .padding(11)
                .background(inner, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(locked)
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))
    }

    private var sessionCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESTADO")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(muted)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
        .padding(13)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(line, lineWidth: 1))
    }

    private var statusText: String {
        if locked { return "BLOQUEADO · FALTA LA KEY" }
        switch engine.phase {
        case .idle: return "LISTO"
        case .working(let t): return t.uppercased()
        case .on(let t): return "ACTIVO · \(t)".uppercased()
        case .off(let t): return "RESTAURADO · \(t)".uppercased()
        case .failed(let t): return t.uppercased()
        }
    }

    private var statusColor: Color {
        if locked { return red }
        switch engine.phase {
        case .on: return green
        case .working: return accent
        case .failed: return red
        default: return muted
        }
    }

    private var footer: some View {
        HStack {
            Button {
                if let url = URL(string: EroMeLink.contact) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Comprar o contacto")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Mantén pulsado arriba para avanzado")
                .font(.system(size: 9))
                .foregroundStyle(muted.opacity(0.6))
        }
        .padding(.bottom, 10)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: date)
    }

    private func openGame() {
        attempt(["freefiremax://", "freefire://"])
    }

    private func attempt(_ schemes: [String]) {
        guard let first = schemes.first, let url = URL(string: first) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok, schemes.count > 1 {
                attempt(Array(schemes.dropFirst()))
            }
        }
    }
}
