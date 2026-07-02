import Foundation
import CSVKit

/// Application Support 配下の軽量JSON永続化(仕様書 §9.4)。
/// - mapping-presets.json : カラムマッピングのプリセット
/// - transfer-history.json : 転送履歴(直近10件、表示名と件数のみ)
enum AppStorageFiles {

    struct TransferHistoryEntry: Codable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        /// 相手端末の表示名 or "CSVインポート" 等(個人データは持たない)
        var counterpart: String
        var created: Int
        var merged: Int
        var skipped: Int
        var failed: Int
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var presetsURL: URL { directory.appendingPathComponent("mapping-presets.json") }
    private static var historyURL: URL { directory.appendingPathComponent("transfer-history.json") }

    // MARK: - マッピングプリセット

    static func loadMappingPresets() -> [ColumnMapping] {
        guard let data = try? Data(contentsOf: presetsURL) else { return [] }
        return (try? JSONDecoder().decode([ColumnMapping].self, from: data)) ?? []
    }

    static func saveMappingPresets(_ presets: [ColumnMapping]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL, options: .atomic)
    }

    // MARK: - 転送履歴

    static func loadHistory() -> [TransferHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([TransferHistoryEntry].self, from: data)) ?? []
    }

    static func appendHistory(_ entry: TransferHistoryEntry) {
        var entries = loadHistory()
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(10))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    static func clearHistory() {
        try? FileManager.default.removeItem(at: historyURL)
    }
}
