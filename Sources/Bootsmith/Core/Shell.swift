import Foundation

/// Execução de processos auxiliares. Sempre com caminho absoluto e argumentos
/// separados — nunca uma string de shell — para que nada em um nome de arquivo
/// possa ser interpretado como comando.
enum Shell {
    enum Failure: LocalizedError {
        case nonZeroExit(command: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let command, let status, let output):
                "\(command) terminou com status \(status): \(output)"
            }
        }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure.nonZeroExit(command: executable, status: process.terminationStatus, output: output)
        }
        return output
    }
}
