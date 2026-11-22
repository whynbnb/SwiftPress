import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, let build {
            return "v\(version) (\(build))"
        }
        if let version {
            return "v\(version)"
        }
        return "dev"
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: "App")!
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)

            Text("SwiftPress")
                .font(.title2)
                .fontWeight(.bold)

            Text(appVersion)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(L10n.tr("about.subtitle"))
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(L10n.tr("about.license"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("MIT")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                if let repoURL = URL(string: "https://github.com/whynbnb/SwiftPress") {
                    HStack(spacing: 4) {
                        Text(L10n.tr("about.repo"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("github.com/whynbnb/SwiftPress", destination: repoURL)
                            .font(.caption)
                    }
                }
            }

            Spacer()

            Text(L10n.tr("about.copyright"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 280, height: 380)
        .preferredColorScheme(settings.resolvedColorScheme)
    }
}
