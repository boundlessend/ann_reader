import SwiftUI
import ANNKit

/// свежий релиз приложения с GitHub Releases API
struct ReleaseInfo: Sendable, Equatable {
    let version: String   // "1.2.0", без префикса v
    let url: URL          // страница релиза для скачивания
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case malformed

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): String(localized: "GitHub returned HTTP \(code).")
        case .malformed: String(localized: "Unexpected response from GitHub.")
        }
    }
}

/// проверка обновлений без Sparkle: сравниваем тег последнего GitHub-релиза
/// с версией бандла; "скачать" - это переход на страницу релиза в браузере
enum UpdateChecker {
    private static let latestURL =
        URL(string: "https://api.github.com/repos/boundlessend/ann_reader/releases/latest")!

    /// версия из Info.plist; nil в dev-запуске без бандла (swift run)
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        var req = URLRequest(url: latestURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse(http.statusCode)
        }
        struct Release: Decodable {
            let tag_name: String
            let html_url: String
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let url = URL(string: release.html_url) else {
            throw UpdateError.malformed
        }
        let version = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst()) : release.tag_name
        return ReleaseInfo(version: version, url: url)
    }

    /// покомпонентное сравнение версий: "1.10.0" новее "1.9.0"
    static func isNewer(_ latest: String, than current: String) -> Bool {
        current.compare(latest, options: .numeric) == .orderedAscending
    }
}

/// настройки приложения (Cmd+,): версия и ручная проверка обновлений
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Updates") {
                LabeledContent("Version", value: UpdateChecker.currentVersion ?? "dev")
                LabeledContent {
                    updateStatus
                } label: {
                    Button("Check for Updates") { Task { await model.checkForUpdates() } }
                        .disabled(model.updateStatus == .checking)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    @ViewBuilder private var updateStatus: some View {
        switch model.updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .available(let release):
            Button {
                NSWorkspace.shared.open(release.url)
            } label: {
                Label("Version \(release.version) is available", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.link)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

/// окошко о новой версии в стиле приложения: те же glass-подложка и
/// bounce-анимация символа, что у закладки в читалке
struct UpdateSheetView: View {
    let release: ReleaseInfo
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: appeared)
            Text("Update available").font(.title2.bold())
            Text("ANN Reader \(release.version) is ready to download. You have \(UpdateChecker.currentVersion ?? "dev").")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Later") { dismiss() }
                Button("Download") {
                    NSWorkspace.shared.open(release.url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 380)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(8)
        .onAppear { appeared = true }
    }
}
