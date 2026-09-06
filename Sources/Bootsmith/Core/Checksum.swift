import Foundation
import CryptoKit

/// Confere o SHA-256 de uma imagem antes de gravá-la.
///
/// Uma ISO corrompida no download grava sem erro nenhum e só se revela na hora
/// de instalar, na frente do servidor. Conferir custa o tempo de uma leitura.
enum Checksum {
    /// Calcula o digest do arquivo como ele está em disco — comprimido ou não.
    /// É esse o número que projetos publicam nos seus `SHA256SUMS`.
    static func sha256(of url: URL, onProgress: @Sendable (Double) -> Void) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        var digest = SHA256()
        var read: Int64 = 0
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            digest.update(data: chunk)
            read += Int64(chunk.count)
            if total > 0 { onProgress(Double(read) / Double(total)) }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Extrai o digest esperado do que o usuário forneceu: ou o hash puro, ou o
    /// conteúdo de um arquivo `SHA256SUMS`, onde cada linha é
    /// `<hash> *<nome do arquivo>`.
    static func expected(from text: String, imageName: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isDigest(trimmed) { return trimmed }

        for line in trimmed.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, isDigest(String(parts[0])) else { continue }
            let name = parts.dropFirst().joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            if name == imageName.lowercased() { return String(parts[0]) }
        }
        return nil
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
