import Foundation
import SwiftUI

/// 設定画面。タイムラインのツールバーから開く。
/// 課金・通知・エクスポート・テーマなどは、ここへセクションを 1 つずつ足していく前提で、
/// セクションごとに独立した View に分けている。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                AboutSection(info: .current)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

// MARK: - このアプリについて

private struct AboutSection: View {
    let info: AppInfo

    @Environment(AppRouter.self) private var router

    var body: some View {
        Section("About") {
            LabeledContent("App") {
                Text(verbatim: info.name)
            }
            LabeledContent("Version") {
                Text(verbatim: info.version)
            }
            LabeledContent("Build") {
                Text(verbatim: info.build)
            }
            Button("View the tutorial again") {
                OnboardingTracker().reset()
                router.replayTutorial()
            }
            .accessibilityIdentifier("settings.replayTutorial")
        }
    }
}

/// Info.plist から読むアプリの基本情報。
struct AppInfo: Equatable {
    var name: String
    var version: String
    var build: String

    /// 実行中のアプリ本体の情報。表示名はローカライズ済みの値（InfoPlist.xcstrings）を優先する。
    static var current: AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            infoDictionary: bundle.infoDictionary ?? [:],
            localizedInfoDictionary: bundle.localizedInfoDictionary ?? [:]
        )
    }

    init(name: String, version: String, build: String) {
        self.name = name
        self.version = version
        self.build = build
    }

    init(infoDictionary: [String: Any], localizedInfoDictionary: [String: Any] = [:]) {
        func value(_ key: String) -> String? {
            (localizedInfoDictionary[key] as? String) ?? (infoDictionary[key] as? String)
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? ""
        version = value("CFBundleShortVersionString") ?? ""
        build = value("CFBundleVersion") ?? ""
    }
}

#Preview {
    SettingsView()
        .environment(AppRouter())
}
