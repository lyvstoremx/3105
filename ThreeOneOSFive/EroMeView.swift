import SwiftUI
import AVFoundation
import UIKit

final class EroMeVoice {
    private let synth = AVSpeechSynthesizer()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
        utterance.pitchMultiplier = 1.9
        utterance.rate = 0.45
        utterance.volume = 1
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
}

final class EroMeKey: ObservableObject {
    @Published private(set) var key: String = ""
    @Published private(set) var expiry: Date?

    private let keyField = "erome.key"
    private let expiryField = "erome.keyExpiry"
    private let defaultDays: Double = 30

    init() {
        key = UserDefaults.standard.string(forKey: keyField) ?? ""
        if let stamp = UserDefaults.standard.object(forKey: expiryField) as? Date {
            expiry = stamp
        }
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
    @State private var voiceOn = true
    @State private var showAdvanced = false
    private let voice = EroMeVoice()

    private let bg = Color(red: 0.047, green: 0.047, blue: 0.063)
    private let card = Color(red: 0.071, green: 0.071, blue: 0.094)
    private let line = Color(red: 0.137, green: 0.137, blue: 0.169)
    private let accent = Color(red: 0.910, green: 0.376, blue: 0.557)
    private let muted = Color(red: 0.545, green: 0.545, blue: 0.588)

    private var loaded: Int { EroMeOption.all.count - engine.missing.count }
    private var activeCount: Int { engine.active.count }
    private var locked: Bool { !keyStore.isValid }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    keyCard
                    patchCard
                    section("Aimbots", "al activar uno se apaga el otro")
                    ForEach(EroMeOption.all.filter { $0.kind == .aimbot }) { row($0) }
                    section("Hologramas", "independientes")
                        .padding(.top, 6)
                    ForEach(EroMeOption.all.filter { $0.kind == .hologram }) { row($0) }
                    statusBar
                    footer
                }
                .padding(16)
            }
        }
        .onAppear { engine.bootstrap() }
        .onChange(of: engine.phase) { phase in
            if case .on = phase, voiceOn { voice.say("Levi activado") }
        }
        .fullScreenCover(isPresented: $showAdvanced) {
            ContentView()
                .environmentObject(AppState())
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                Text("EroMe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(activeCount > 0 ? "\(activeCount) activo\(activeCount == 1 ? "" : "s")" : "sin activar")
                .font(.system(size: 11))
                .foregroundStyle(activeCount > 0 ? accent : muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(card, in: Capsule())
                .overlay(Capsule().stroke(activeCount > 0 ? accent : line, lineWidth: 1))
        }
        .padding(.bottom, 16)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Tu key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if keyStore.isValid {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(keyStore.remaining(from: context.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accent)
                    }
                } else {
                    Text(keyStore.key.isEmpty ? "sin key" : "vencida")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                }
            }

            if keyStore.key.isEmpty || !keyStore.isValid {
                TextField("EROME-XXXX-XXXX-XXXX", text: $keyInput)
                    .font(.system(size: 12, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(bg, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(line, lineWidth: 1))
                    .foregroundStyle(.white)

                Button {
                    keyStore.save(keyInput)
                    keyInput = ""
                } label: {
                    Text("Guardar key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(accent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text(maskedKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(muted)
                    Spacer()
                    Button("Cambiar") { keyStore.clear() }
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                }
            }

            Rectangle()
                .fill(line)
                .frame(height: 1)
                .padding(.vertical, 1)

            HStack {
                Text("Dispositivos permitidos")
                    .font(.system(size: 10))
                    .foregroundStyle(muted)
                Spacer()
                Text("1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }

            HStack {
                Text("iOS soportado")
                    .font(.system(size: 10))
                    .foregroundStyle(muted)
                Spacer()
                Text("26.0 – 26.6.1 · 27 beta")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
            }
        }
        .padding(12)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(keyStore.isValid ? accent : line, lineWidth: 1))
        .padding(.bottom, 12)
    }

    private var maskedKey: String {
        let k = keyStore.key
        guard k.count > 8 else { return k }
        return String(k.prefix(4)) + "-••••-" + String(k.suffix(4))
    }

    private var patchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Parches cargados")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                Spacer()
                Text("\(loaded) de \(EroMeOption.all.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(loaded == EroMeOption.all.count ? Color(red: 0.373, green: 0.816, blue: 0.541) : accent)
            }
            ProgressView(value: Double(loaded), total: Double(EroMeOption.all.count))
                .tint(accent)
            if loaded == 0 {
                Text("Todavía no hay parches subidos. Los switches se activan cuando estén.")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
        }
        .padding(12)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(line, lineWidth: 1))
        .padding(.bottom, 16)
    }

    private func section(_ title: String, _ tag: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(tag)
        }
        .font(.system(size: 11))
        .foregroundStyle(muted)
        .padding(.bottom, 7)
    }

    private func row(_ option: EroMeOption) -> some View {
        let on = engine.active.contains(option.id)
        let working = engine.busy == option.id
        let unavailable = engine.missing.contains(option.id)

        return Button {
            engine.toggle(option)
        } label: {
            HStack(spacing: 10) {
                Text(option.title)
                    .font(.system(size: 13))
                    .foregroundStyle(unavailable || locked ? muted : .white)
                Spacer()
                Text(working ? "···" : (on ? "on" : "off"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(on ? bg : muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(on ? accent : card, in: Capsule())
                    .overlay(Capsule().stroke(on ? accent : line, lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(on ? Color(red: 0.102, green: 0.071, blue: 0.094) : card,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(on ? accent : line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(engine.busy != nil || unavailable || locked)
        .opacity(unavailable || locked ? 0.45 : 1)
        .padding(.bottom, 7)
    }

    private var statusBar: some View {
        Text(locked ? "Introduce una key para desbloquear" : statusText)
            .font(.system(size: 12))
            .foregroundStyle(locked ? muted : statusColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(line, lineWidth: 1))
            .padding(.top, 5)
    }

    private var statusText: String {
        switch engine.phase {
        case .idle: return "Sin activar"
        case .working(let t): return t
        case .on(let t): return "\(t) · on"
        case .off(let t): return "\(t) · off, archivos restaurados"
        case .failed(let t): return t
        }
    }

    private var statusColor: Color {
        switch engine.phase {
        case .on: return Color(red: 0.373, green: 0.816, blue: 0.541)
        case .working: return accent
        case .failed: return Color(red: 0.937, green: 0.42, blue: 0.42)
        default: return muted
        }
    }

    private var footer: some View {
        HStack {
            Button("Comprar o contacto") {
                if let url = URL(string: EroMeLink.contact) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(muted)

            Spacer()

            Button(voiceOn ? "Voz: on" : "Voz: off") {
                voiceOn.toggle()
                if voiceOn { voice.say("Levi activado") }
            }
            .font(.system(size: 11))
            .foregroundStyle(voiceOn ? muted : line)

            Button("Avanzado") { showAdvanced = true }
                .font(.system(size: 11))
                .foregroundStyle(muted)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
