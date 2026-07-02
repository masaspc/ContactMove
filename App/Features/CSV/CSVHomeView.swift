import SwiftUI

/// CSV/vCard 機能の入口(エクスポート/インポートの選択)。
struct CSVHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LimitedAccessBanner()

                NavigationLink {
                    ExportView()
                } label: {
                    MenuCard(
                        title: "エクスポート",
                        subtitle: "連絡先をCSV(Excel対応)またはvCardへ書き出し",
                        systemImage: "square.and.arrow.up.fill",
                        tint: .green)
                }

                NavigationLink {
                    ImportFlowView()
                } label: {
                    MenuCard(
                        title: "インポート",
                        subtitle: "CSV / vCard ファイルから連絡先を取り込み",
                        systemImage: "square.and.arrow.down.fill",
                        tint: .teal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("ヒント", systemImage: "lightbulb")
                        .font(.subheadline.bold())
                    Text("CSVはUTF-8(BOM付き)で書き出すため、Excel(日本語環境)でも文字化けしません。画像を含めたい場合はvCardを選んでください。GoogleコンタクトやOutlookのCSV、Shift_JISのファイルも取り込めます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("CSV / vCard")
    }
}
