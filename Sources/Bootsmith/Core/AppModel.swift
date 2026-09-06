import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case unmounting
        case writing(Flasher.Progress)
        case verifying(Double)
        case done(bytes: Int64, verified: Bool, ejected: Bool)
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.unmounting, .unmounting): true
            case (.writing(let a), .writing(let b)): a.bytesWritten == b.bytesWritten
            case (.verifying(let a), .verifying(let b)): a == b
            case (.done(let a, let b, let c), .done(let d, let e, let f)): a == d && b == e && c == f
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    private(set) var drives: [Drive] = []
    private(set) var phase: Phase = .idle
    var image: DiskImage?
    var selectedDriveID: Drive.ID?

    var language: Language {
        didSet {
            Defaults.language = language
            L.current = language.resolved
        }
    }
    var verifyAfterWrite: Bool { didSet { Defaults.verifyAfterWrite = verifyAfterWrite } }
    var ejectAfterWrite: Bool { didSet { Defaults.ejectAfterWrite = ejectAfterWrite } }

    private var task: Task<Void, Never>?

    init() {
        language = Defaults.language
        verifyAfterWrite = Defaults.verifyAfterWrite
        ejectAfterWrite = Defaults.ejectAfterWrite
        L.current = language.resolved
        refreshDrives()
    }

    var selectedDrive: Drive? {
        drives.first { $0.id == selectedDriveID }
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .failed: false
        default: true
        }
    }

    var canWrite: Bool {
        guard !isBusy, let image, let drive = selectedDrive else { return false }
        return image.boot.isBootable && image.size <= drive.size
    }

    func refreshDrives() {
        drives = (try? DriveScanner().scan()) ?? []
        // Se o dispositivo escolhido sumiu (o usuário desconectou), não deixamos
        // uma seleção pendurada apontando para nada.
        if let id = selectedDriveID, !drives.contains(where: { $0.id == id }) {
            selectedDriveID = nil
        }
        if selectedDriveID == nil, drives.count == 1 {
            selectedDriveID = drives[0].id
        }
    }

    func load(_ url: URL) {
        do {
            image = try ImageInspector().inspect(url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func write() {
        guard let image, let drive = selectedDrive else { return }
        phase = .unmounting

        task = Task { [weak self] in
            guard let self else { return }
            let flasher = Flasher(image: image, drive: drive)
            let shouldVerify = verifyAfterWrite
            do {
                let verified = try await flasher.flash(
                    verify: shouldVerify,
                    onProgress: { progress in
                        Task { @MainActor in self.phase = .writing(progress) }
                    },
                    onVerifyProgress: { fraction in
                        Task { @MainActor in self.phase = .verifying(fraction) }
                    }
                )

                var ejected = false
                if ejectAfterWrite, verified {
                    Flasher.eject(drive)
                    ejected = true
                }

                phase = .done(bytes: image.size, verified: verified, ejected: ejected)
                refreshDrives()
            } catch let error as Flasher.FlashError {
                phase = .failed(error.localized)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        phase = .idle
        refreshDrives()
    }
}
