import Foundation

/// Grava uma imagem num disco inteiro.
///
/// Escrever em `/dev/rdiskN` esbarra em duas barreiras independentes: as
/// permissões Unix (o nó pertence a root) e o TCC, que desde o macOS 13 protege
/// volumes removíveis. Elevar com `osascript … with administrator privileges`
/// resolve a primeira e falha na segunda — o processo elevado roda num contexto
/// próprio e não herda o Acesso Total ao Disco concedido ao app.
///
/// Por isso usamos `authopen`: um utilitário setuid do próprio macOS que pede a
/// autorização, abre o arquivo como root e continua sendo filho do app, de modo
/// que o TCC o avalia pelo app responsável. Nada fica instalado na máquina, e a
/// senha nunca passa por nós.
struct Flasher: Sendable {
    enum FlashError: LocalizedError {
        case imageLargerThanDrive(image: Int64, drive: Int64)
        case authorizationDenied
        case accessDenied(String)
        case writeFailed(status: Int32, detail: String)

        /// Texto em inglês, para logs. A UI usa `localized`, que traduz — a
        /// conformidade com `LocalizedError` é nonisolated e não pode alcançar
        /// a tabela de tradução, que vive no MainActor.
        var errorDescription: String? { compose { $0 } }

        @MainActor
        var localized: String { compose { L.t($0) } }

        private func compose(_ translate: (String) -> String) -> String {
            switch self {
            case .imageLargerThanDrive(let image, let drive):
                let i = ByteCountFormatter.string(fromByteCount: image, countStyle: .file)
                let d = ByteCountFormatter.string(fromByteCount: drive, countStyle: .file)
                return String(format: translate("The image is %@ and the device only has %@."), i, d)
            case .authorizationDenied:
                return translate("Authorization cancelled — nothing was written.")
            case .accessDenied(let device):
                return String(format: translate("macOS blocked access to %@. Grant Full Disk Access to Bootsmith in System Settings › Privacy & Security, then reopen the app."), device)
            case .writeFailed(let status, let detail):
                return String(format: translate("The write failed (status %d). %@"), Int(status), detail)
            }
        }
    }

    struct Progress: Sendable {
        var bytesWritten: Int64
        var totalBytes: Int64
        /// Média móvel, para a estimativa não oscilar a cada bloco.
        var bytesPerSecond: Double

        var fraction: Double {
            totalBytes > 0 ? min(1, Double(bytesWritten) / Double(totalBytes)) : 0
        }

        var remaining: TimeInterval? {
            guard bytesPerSecond > 0, bytesWritten < totalBytes else { return nil }
            return Double(totalBytes - bytesWritten) / bytesPerSecond
        }
    }

    let image: DiskImage
    let drive: Drive

    /// 4 MiB: o mesmo bloco que o `dd` usa por convenção em pendrives. Blocos
    /// menores multiplicam syscalls sem ganho; maiores não aceleram mais nada.
    private static let chunkSize = 4 * 1024 * 1024

    func flash(onProgress: @Sendable @escaping (Progress) -> Void) async throws {
        guard image.size <= drive.size else {
            throw FlashError.imageLargerThanDrive(image: image.size, drive: drive.size)
        }

        // Desmontar é obrigatório: com um volume montado o kernel recusa a
        // escrita no dispositivo inteiro.
        _ = try? Shell.run("/usr/sbin/diskutil", ["unmountDisk", drive.deviceNode])

        let source = try FileHandle(forReadingFrom: image.url)
        defer { try? source.close() }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/libexec/authopen")
        // -w escreve o que vier do stdin; O_WRONLY abre o nó bruto para escrita.
        process.arguments = ["-w", "-o", "\(O_WRONLY)", drive.rawDeviceNode]

        let input = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardError = errors
        process.standardOutput = Pipe()

        try process.run()

        var written: Int64 = 0
        let started = Date()
        var lastReport = Date.distantPast

        do {
            while true {
                guard let chunk = try source.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
                try input.fileHandleForWriting.write(contentsOf: chunk)
                written += Int64(chunk.count)

                // Reportar a cada bloco inundaria a UI; 4 vezes por segundo basta.
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = Date()
                    let elapsed = Date().timeIntervalSince(started)
                    onProgress(Progress(bytesWritten: written, totalBytes: image.size,
                                        bytesPerSecond: elapsed > 0 ? Double(written) / elapsed : 0))
                }
            }
        } catch {
            // O pipe quebra quando o authopen morre — a causa real está no stderr.
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
            throw Self.interpret(process: process, errors: errors, device: drive.rawDeviceNode)
        }

        try? input.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Self.interpret(process: process, errors: errors, device: drive.rawDeviceNode)
        }

        let elapsed = Date().timeIntervalSince(started)
        onProgress(Progress(bytesWritten: image.size, totalBytes: image.size,
                            bytesPerSecond: elapsed > 0 ? Double(written) / elapsed : 0))
    }

    /// Traduz a saída do `authopen` em algo acionável. "Operation not permitted"
    /// com o processo já rodando como root significa TCC, não permissão Unix —
    /// e essa distinção é a diferença entre o usuário saber ou não o que fazer.
    private static func interpret(process: Process, errors: Pipe, device: String) -> FlashError {
        let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if detail.contains("not permitted") || detail.contains("Operation not permitted") {
            return .accessDenied(device)
        }
        if detail.isEmpty && process.terminationStatus == 1 {
            return .authorizationDenied
        }
        return .writeFailed(status: process.terminationStatus, detail: detail)
    }

    /// Ejeta ao final para que o usuário possa remover o pendrive com segurança.
    static func eject(_ drive: Drive) {
        _ = try? Shell.run("/usr/sbin/diskutil", ["eject", drive.deviceNode])
    }
}
