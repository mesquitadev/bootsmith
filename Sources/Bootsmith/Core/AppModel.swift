import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case erasing
        case erased(String)
        case unmounting
        case writing(Flasher.Progress)
        case verifying(Double)
        case done(bytes: Int64, verified: Bool, ejected: Bool)
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.unmounting, .unmounting), (.erasing, .erasing): true
            case (.erased(let a), .erased(let b)): a == b
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
    private let watcher = DriveWatcher()

    /// Texto que o usuário colou: um SHA-256 ou o conteúdo de um SHA256SUMS.
    var checksumInput: String = ""
    private(set) var checksumResult: ChecksumResult?

    enum ChecksumResult: Equatable {
        case checking(Double)
        case matched
        case mismatched(expected: String, actual: String)
        case notFound

        var isFailure: Bool {
            switch self {
            case .mismatched, .notFound: true
            default: false
            }
        }
    }

    init() {
        language = Defaults.language
        verifyAfterWrite = Defaults.verifyAfterWrite
        ejectAfterWrite = Defaults.ejectAfterWrite
        L.current = language.resolved
        refreshDrives()

        // A lista passa a se manter sozinha: plugar ou remover um pendrive
        // aparece na tela sem que ninguém precise clicar em Atualizar.
        watcher.onChange = { [weak self] drives in
            guard let self, !isBusy else { return }
            self.drives = drives
            if let id = selectedDriveID, !drives.contains(where: { $0.id == id }) {
                selectedDriveID = nil
            }
            if selectedDriveID == nil, drives.count == 1 {
                selectedDriveID = drives[0].id
            }
        }
        watcher.start()
    }

    /// Confere o digest da imagem contra o que o usuário forneceu.
    func verifyChecksum() {
        guard let image else { return }
        guard let expected = Checksum.expected(from: checksumInput, imageName: image.name) else {
            checksumResult = .notFound
            return
        }
        checksumResult = .checking(0)

        Task { [weak self] in
            guard let self else { return }
            let url = image.url
            let actual = await Task.detached(priority: .userInitiated) { () -> String? in
                try? Checksum.sha256(of: url) { fraction in
                    Task { @MainActor in self.checksumResult = .checking(fraction) }
                }
            }.value
            guard let actual else { checksumResult = .notFound; return }
            checksumResult = actual == expected ? .matched : .mismatched(expected: expected, actual: actual)
        }
    }

    /// Reformata o dispositivo para uso comum.
    func erase(as filesystem: DriveEraser.Filesystem, named name: String) {
        guard let drive = selectedDrive, !isBusy else { return }
        phase = .erasing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try DriveEraser.erase(drive, as: filesystem, named: name)
                }.value
                phase = .erased(filesystem.shortLabel)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            refreshDrives()
        }
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
        checksumResult = nil
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
