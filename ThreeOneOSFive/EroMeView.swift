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

struct EroMeView: View {
    @StateObject private var engine = EroMeEngine()
    @State private var voiceOn = true
    @State private var showAdvanced = false
    private let voice = EroMeVoice()

    private let bg = Color(red: 0.047, green: 0.047, blue: 0.063)
    private let card = Color(red: 0.071, green: 0.071, blue: 0.094)
    private let line = Color(red: 0.137, green: 0.137, blue: 0.169)
    private let accent = Color(red: 0.910, green: 0.376, blue: 0.557)
    private let muted = Color(red: 0.545, green: 0.545, blue: 0.588)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Text("Free Fire · cierra el juego antes de aplicar")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 14)

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
            Text("beta")
                .font(.system(size: 11))
                .foregroundStyle(muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(card, in: Capsule())
                .overlay(Capsule().stroke(line, lineWidth: 1))
        }
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
                    .foregroundStyle(unavailable ? muted : .white)
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
        .disabled(engine.busy != nil || unavailable)
        .opacity(unavailable ? 0.45 : 1)
        .padding(.bottom, 7)
    }

    private var statusBar: some View {
        Text(statusText)
            .font(.system(size: 12))
            .foregroundStyle(statusColor)
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
        .padding(.top, 11)
    }
}
