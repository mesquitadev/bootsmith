import Foundation

/// Idiomas que o app fala. Inglês é o padrão; a preferência do sistema só é
/// seguida quando o usuário escolhe "System".
enum Language: String, CaseIterable, Identifiable, Sendable {
    case system, en, ptBR = "pt-BR"

    var id: String { rawValue }

    /// Cada idioma se nomeia no próprio idioma.
    var label: String {
        switch self {
        case .system: "System"
        case .en: "English"
        case .ptBR: "Português (Brasil)"
        }
    }

    var resolved: Language {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("pt") ? .ptBR : .en
    }
}

/// Tradução por tabela em Swift, e não `.lproj`: o executável do SwiftPM não
/// carrega bundles de recurso fora do `.app`, e trocar de idioma sem reiniciar
/// exigiria recarregar o bundle à mão. Aqui é só estado observado pela UI.
@MainActor
enum L {
    static var current: Language = Defaults.language.resolved

    /// A chave é o texto em inglês, então uma entrada faltante cai em inglês em
    /// vez de aparecer como identificador cru.
    static func t(_ key: String) -> String {
        guard current == .ptBR, let translated = ptBR[key] else { return key }
        return translated
    }
}
