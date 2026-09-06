import SwiftUI

struct AboutView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bootsmith").font(.title.weight(.semibold))
                    Text(L.t("Bootable USB drives for BIOS and UEFI."))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(String(format: L.t("Version %@"), Self.version))
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    row(L.t("Developer"), "Paulo Victor Mesquita", "https://github.com/mesquitadev")
                    row(L.t("Source"), "github.com/mesquitadev/bootsmith", "https://github.com/mesquitadev/bootsmith")
                }
                Divider()
                Text(L.t("Free and open source under the MIT license."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }

    private func row(_ label: String, _ text: String, _ url: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Link(text, destination: URL(string: url)!).font(.callout)
        }
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
