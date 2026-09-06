import Foundation

/// Preferências do app.
enum Defaults {
    private static let store = UserDefaults.standard

    enum Key {
        static let language = "language"
        static let verifyAfterWrite = "verifyAfterWrite"
        static let ejectAfterWrite = "ejectAfterWrite"
    }

    static var language: Language {
        get { Language(rawValue: store.string(forKey: Key.language) ?? "") ?? .en }
        set { store.set(newValue.rawValue, forKey: Key.language) }
    }

    /// Reler o dispositivo e comparar com a imagem. Custa o mesmo tempo da
    /// gravação, e é a única forma de saber que o pendrive não está corrompido
    /// antes de descobrir isso na frente do servidor.
    static var verifyAfterWrite: Bool {
        get { store.object(forKey: Key.verifyAfterWrite) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.verifyAfterWrite) }
    }

    static var ejectAfterWrite: Bool {
        get { store.object(forKey: Key.ejectAfterWrite) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.ejectAfterWrite) }
    }
}
