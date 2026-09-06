import Foundation
import CryptoKit

/// Confere que o dispositivo recebeu exatamente a imagem.
///
/// Um pendrive pode aceitar toda a escrita e ainda assim conter lixo — memória
/// flash gasta, cabo ruim, adaptador barato. Descobrir isso aqui custa alguns
/// minutos; descobrir na frente do servidor custa uma viagem.
struct Verifier: Sendable {
    let image: DiskImage
    let drive: Drive

    private static let chunkSize = 4 * 1024 * 1024

    /// Lê do dispositivo a mesma quantidade de bytes da imagem e compara os
    /// digests. Só os bytes da imagem: o resto do pendrive é espaço não usado.
    func verify(onProgress: @Sendable @escaping (Double) -> Void) async throws -> Bool {
        let source = try FileHandle(forReadingFrom: image.url)
        defer { try? source.close() }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/libexec/authopen")
        process.arguments = ["-stdoutpipe", "-o", "\(O_RDONLY)", drive.rawDeviceNode]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()

        var imageDigest = SHA256()
        var deviceDigest = SHA256()
        var read: Int64 = 0

        while read < image.size {
            let remaining = Int(min(Int64(Self.chunkSize), image.size - read))
            guard let expected = try source.read(upToCount: remaining), !expected.isEmpty else { break }
            let actual = output.fileHandleForReading.readData(ofLength: expected.count)
            guard actual.count == expected.count else { break }

            imageDigest.update(data: expected)
            deviceDigest.update(data: actual)
            read += Int64(expected.count)
            onProgress(Double(read) / Double(image.size))
        }

        process.terminate()
        process.waitUntilExit()

        guard read == image.size else { return false }
        return imageDigest.finalize() == deviceDigest.finalize()
    }
}
