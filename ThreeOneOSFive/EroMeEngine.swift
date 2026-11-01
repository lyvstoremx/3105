import Foundation
import SwiftUI

enum EroMeKind { case aimbot, hologram }

struct EroMeOption: Identifiable, Hashable {
    let id: String
    let title: String
    let resource: String
    let kind: EroMeKind

    static let all: [EroMeOption] = [
        .init(id: "aim_drag", title: "AimDrag", resource: "aim_drag", kind: .aimbot),
        .init(id: "aim_head", title: "Aimbot Head", resource: "aim_head", kind: .aimbot),
        .init(id: "aim_cuello", title: "Aimbot Cuello", resource: "aim_cuello", kind: .aimbot),
        .init(id: "holo_armas", title: "Holograma de armas", resource: "holo_armas", kind: .hologram),
        .init(id: "holo_personajes", title: "Holograma de personajes", resource: "holo_personajes", kind: .hologram)
    ]
}

enum EroMeLink {
    static let contact = "https://t.me/EroMExternalios"
}

@MainActor
final class EroMeEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(String)
        case on(String)
        case off(String)
        case failed(String)
    }

    @Published private(set) var active: Set<String> = []
    @Published private(set) var missing: Set<String> = []
    @Published private(set) var busy: String?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var booted = false

    private var cache: [String: PatchProject] = [:]

    func bootstrap() {
        guard !booted else { return }
        booted = true
        for option in EroMeOption.all where project(for: option) == nil {
            missing.insert(option.id)
        }
        refreshActive()
    }

    func refreshActive() {
        var on = Set<String>()
        for option in EroMeOption.all {
            guard let project = project(for: option) else { continue }
            if DevicePatchService.latestReceipt(projectID: project.id) != nil { on.insert(option.id) }
        }
        active = on
    }

    func toggle(_ option: EroMeOption) {
        guard busy == nil else { return }
        if active.contains(option.id) { restore(option) } else { apply(option) }
    }

    private func apply(_ option: EroMeOption) {
        guard let project = project(for: option) else {
            phase = .failed("Falta el parche \(option.title)")
            return
        }
        busy = option.id
        let previous = EroMeOption.all.first {
            $0.kind == .aimbot && $0.id != option.id && active.contains($0.id)
        }

        Task.detached(priority: .userInitiated) {
            do {
                if let previous, let prevProject = await self.project(for: previous) {
                    await MainActor.run { self.phase = .working("Restaurando \(previous.title)…") }
                    if let receipt = DevicePatchService.latestReceipt(projectID: prevProject.id) {
                        try DevicePatchService.restore(receipt: receipt)
                        await MainActor.run { _ = self.active.remove(previous.id) }
                    }
                }
                await MainActor.run { self.phase = .working("Aplicando \(option.title)…") }
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    _ = self.active.insert(option.id)
                    self.busy = nil
                    self.phase = .on(option.title)
                }
            } catch {
                await MainActor.run {
                    self.busy = nil
                    self.phase = .failed(Self.describe(error))
                }
            }
        }
    }

    private func restore(_ option: EroMeOption) {
        guard let project = project(for: option) else {
            phase = .failed("Falta el parche \(option.title)")
            return
        }
        guard let receipt = DevicePatchService.latestReceipt(projectID: project.id) else {
            active.remove(option.id)
            phase = .off(option.title)
            return
        }
        busy = option.id
        Task.detached(priority: .userInitiated) {
            do {
                await MainActor.run { self.phase = .working("Quitando \(option.title)…") }
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    _ = self.active.remove(option.id)
                    self.busy = nil
                    self.phase = .off(option.title)
                }
            } catch {
                await MainActor.run {
                    self.busy = nil
                    self.phase = .failed(Self.describe(error))
                }
            }
        }
    }

    private func project(for option: EroMeOption) -> PatchProject? {
        if let cached = cache[option.id] { return cached }
        guard let url = Bundle.main.url(
                forResource: option.resource,
                withExtension: "3105",
                subdirectory: "Patches"
              ),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let decoded = try? PatchPackageCodec.decode(data, password: nil) else {
            return nil
        }
        cache[option.id] = decoded.project
        return decoded.project
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? PatchPackageError else {
            return "Error inesperado"
        }
        switch error {
        case .targetAppUnavailable: return "Free Fire no está instalado"
        case .applyFailed: return "No se pudo aplicar, revisa el parche"
        case .restoreFailed: return "No se pudo restaurar"
        case .duplicateTarget: return "El parche repite una ruta"
        case .unsafeTargetPath: return "Ruta no permitida en el parche"
        case .invalidPasswordOrCorruptedPackage: return "El parche está dañado"
        case .sizeLimitExceeded: return "El parche pesa demasiado"
        case .unsupportedVersion: return "Versión de parche no soportada"
        case .symbolicLinkUnsupported: return "Enlace simbólico no soportado"
        default: return "Fallo del motor"
        }
    }
}
