import SwiftUI
import Models

/// 対象選択リスト(全件/検索/個別チェック、仕様書 FR-12)。
/// 大量データ向けに LazyVStack + 検索絞り込みで表示する。
struct ContactSelectionView: View {
    let contacts: [TransferContact]
    @Binding var selectedIDs: Set<UUID>
    @State private var searchText = ""

    private var filtered: [TransferContact] {
        guard !searchText.isEmpty else { return contacts }
        let query = searchText.lowercased()
        return contacts.filter { contact in
            contact.displayName.lowercased().contains(query)
                || (contact.organizationName ?? "").lowercased().contains(query)
                || contact.phones.contains { $0.value.contains(query) }
                || contact.emails.contains { $0.value.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(selectedIDs.count) / \(contacts.count) 件を選択中")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全選択") { selectedIDs = Set(contacts.map(\.id)) }
                    .font(.footnote)
                Button("全解除") { selectedIDs = [] }
                    .font(.footnote)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { contact in
                        Button {
                            if selectedIDs.contains(contact.id) {
                                selectedIDs.remove(contact.id)
                            } else {
                                selectedIDs.insert(contact.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedIDs.contains(contact.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(contact.id)
                                                     ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if let detail = detailText(for: contact) {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .accessibilityLabel(Text("\(contact.displayName)、\(selectedIDs.contains(contact.id) ? "選択中" : "未選択")"))
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "名前・会社・電話・メールで検索")
        }
    }

    private func detailText(for contact: TransferContact) -> String? {
        if let phone = contact.phones.first?.value, !phone.isEmpty { return phone }
        if let email = contact.emails.first?.value, !email.isEmpty { return email }
        return nil
    }
}
