import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(L.t("Language"), selection: Binding(
                    get: { model.language }, set: { model.language = $0 })) {
                    ForEach(Language.allCases) { language in
                        Text(language == .system ? L.t("System") : language.label).tag(language)
                    }
                }
            }
            Section {
                Toggle(L.t("Verify after writing"), isOn: Binding(
                    get: { model.verifyAfterWrite }, set: { model.verifyAfterWrite = $0 }))
                Toggle(L.t("Eject when finished"), isOn: Binding(
                    get: { model.ejectAfterWrite }, set: { model.ejectAfterWrite = $0 }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 220)
    }
}
