import SwiftUI
import UIKit
import Models
import DedupeKit
import ContactsKit
import TransferKit

// MARK: - 役割選択(仕様書 §8)

struct TransferRoleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LimitedAccessBanner()

                NavigationLink {
                    TransferFlowView(role: .sender)
                } label: {
                    MenuCard(
                        title: "送信する(この端末から)",
                        subtitle: "旧端末側。連絡先を選んで近くの端末へ送ります",
                        systemImage: "arrow.up.circle.fill",
                        tint: .blue)
                }

                NavigationLink {
                    TransferFlowView(role: .receiver)
                } label: {
                    MenuCard(
                        title: "受信する(この端末へ)",
                        subtitle: "新端末側。送信側からの接続を待ち受けます",
                        systemImage: "arrow.down.circle.fill",
                        tint: .indigo)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("使い方", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("両方の端末でこのアプリを開き、片方で「送信」、もう片方で「受信」を選びます。Bluetooth と Wi-Fi をオンにして端末を近づけてください。接続時に両画面へ同じ4桁コードが表示されます。転送中は画面を開いたままにしてください。")
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
        .navigationTitle("端末間転送")
    }
}

// MARK: - 転送フローの状態管理

@MainActor
final class TransferViewModel: ObservableObject {

    enum Phase {
        case searching                       // 送信側: ピア探索 / 受信側: 待受
        case verifying(code: String, peer: String)
        case selecting                       // 送信側: 連絡先選択
        case transferring
        case waitingResult                   // 送信側: 受信側の取り込み完了待ち
        case candidates                      // 受信側: L4候補確認
        case applying                        // 受信側: 保存中
        case report(TransferResult)
        case failed(AppError)
        case denied
    }

    let role: TransferRole
    @Published var phase: Phase = .searching
    @Published var error: AppError?
    @Published private(set) var peers: [String] = []
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)

    // 送信側
    @Published private(set) var contacts: [TransferContact] = []
    @Published var selectedIDs: Set<UUID> = []

    // 受信側
    @Published private(set) var analysis: DedupeAnalysis?
    @Published var acceptedCandidateIDs: Set<UUID> = []
    @Published var strategy: MergeStrategy = .skip

    private(set) var session: TransferSession?
    private var eventTask: Task<Void, Never>?
    private var counterpartName = ""

    init(role: TransferRole) {
        self.role = role
    }

    func start() {
        guard session == nil else { return }
        let session = TransferSession(role: role, deviceName: UIDevice.current.name)
        self.session = session
        eventTask = Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        }
        session.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        eventTask?.cancel()
        session?.stop()
        session = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func invite(peer: String) {
        counterpartName = peer
        session?.invite(peerNamed: peer)
    }

    func approve(permissions: ContactsPermissions, imageOption: ImageOption) {
        session?.approveVerification()
        // 承認後の遷移は verified イベントで行うが、送信側は先に連絡先を読み込む
        if role == .sender {
            Task { await loadContacts(permissions: permissions, imageOption: imageOption) }
        }
    }

    func reject() {
        session?.rejectVerification()
    }

    private func loadContacts(permissions: ContactsPermissions, imageOption: ImageOption) async {
        guard await PermissionGate.ensureAccess(permissions) else {
            phase = .denied
            return
        }
        do {
            let all = try await ContactsReader().fetchAll(imageOption: imageOption)
            contacts = all
            selectedIDs = Set(all.map(\.id))
        } catch {
            self.error = .contactsAccessDenied
            phase = .denied
        }
    }

    func send(imageOption: ImageOption) {
        let selected = contacts.filter { selectedIDs.contains($0.id) }
        phase = .transferring
        progress = (0, selected.count)
        Task {
            await session?.send(contacts: selected, includesPhotos: imageOption != .excluded)
        }
    }

    // MARK: - 受信側の取り込み

    private func receiveContacts(_ incoming: [TransferContact],
                                 permissions: ContactsPermissions) async {
        guard await PermissionGate.ensureAccess(permissions) else {
            phase = .denied
            return
        }
        do {
            let existing = try await ContactsReader().fetchAll(imageOption: .excluded)
            let analysis = DedupeEngine().analyze(existing: existing, incoming: incoming)
            self.analysis = analysis
            if analysis.candidates.isEmpty {
                await applyPlan()
            } else {
                acceptedCandidateIDs = []
                phase = .candidates
            }
        } catch {
            phase = .failed(.contactsAccessDenied)
        }
    }

    func applyPlan() async {
        guard let analysis else { return }
        phase = .applying
        let plan = MergePlanner.plan(analysis: analysis, strategy: strategy,
                                     acceptedCandidates: acceptedCandidateIDs)
        do {
            let result = try await ContactsApplier().apply(plan) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = (progress.processed, progress.total)
                }
            }
            AppStorageFiles.appendHistory(.init(
                date: Date(), counterpart: counterpartName.isEmpty ? "端末間転送" : counterpartName,
                created: result.created, merged: result.merged,
                skipped: result.skipped, failed: result.failed.count))
            await session?.sendResult(result)
            phase = .report(result)
        } catch {
            phase = .failed(.saveFailed(underlying: error.localizedDescription))
        }
    }

    // MARK: - イベント処理

    private var pendingPermissions: ContactsPermissions?

    func attach(permissions: ContactsPermissions) {
        pendingPermissions = permissions
    }

    private func handle(_ event: TransferEvent) {
        switch event {
        case .peersChanged(let names):
            peers = names
        case .connecting(let peer):
            counterpartName = peer
        case .verificationRequired(let code, let peer):
            counterpartName = peer
            phase = .verifying(code: code, peer: peer)
        case .verified:
            if role == .sender {
                phase = .selecting
            } else {
                phase = .transferring  // 受信待ち(マニフェスト到着で進捗表示)
            }
        case .manifestReceived(let manifest):
            progress = (0, manifest.totalCount)
        case .progress(let done, let total):
            progress = (done, total)
            if role == .sender, case .selecting = phase {
                phase = .transferring
            }
        case .contactsReceived(let incoming):
            if let permissions = pendingPermissions {
                Task { await receiveContacts(incoming, permissions: permissions) }
            }
        case .resultReceived(let result):
            AppStorageFiles.appendHistory(.init(
                date: Date(), counterpart: counterpartName.isEmpty ? "端末間転送" : counterpartName,
                created: result.created, merged: result.merged,
                skipped: result.skipped, failed: result.failed.count))
            phase = .report(result)
        case .finished:
            break
        case .failed(let appError):
            if case .report = phase { return }  // 完了後の切断通知は無視
            phase = .failed(appError)
        }
        if role == .sender, case .transferring = phase,
           progress.total > 0, progress.done >= progress.total {
            phase = .waitingResult
        }
    }
}

// MARK: - 転送フロー画面

struct TransferFlowView: View {
    @EnvironmentObject private var permissions: ContactsPermissions
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model: TransferViewModel
    @Environment(\.dismiss) private var dismiss

    init(role: TransferRole) {
        _model = StateObject(wrappedValue: TransferViewModel(role: role))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .searching:
                searchingStage
            case .verifying(let code, let peer):
                verifyStage(code: code, peer: peer)
            case .selecting:
                selectingStage
            case .transferring:
                ProgressStageView(
                    title: model.role == .sender ? "転送中…" : "受信中…",
                    done: model.progress.done, total: model.progress.total)
            case .waitingResult:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("相手の端末で取り込みが完了するのを待っています…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .candidates:
                receiverCandidatesStage
            case .applying:
                ProgressStageView(title: "連絡先に保存中…",
                                  done: model.progress.done, total: model.progress.total)
            case .report(let result):
                ResultReportView(result: result) {
                    model.stop()
                    dismiss()
                }
            case .failed(let error):
                failedStage(error)
            case .denied:
                PermissionDeniedView()
            }
        }
        .navigationTitle(model.role == .sender ? "送信" : "受信")
        .appErrorAlert($model.error)
        .onAppear {
            model.attach(permissions: permissions)
            model.strategy = appModel.defaultMergeStrategy
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var searchingStage: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            if model.role == .sender {
                Text("近くの端末を探しています…").font(.headline)
                Text("受信側の端末で「受信する」を開いてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.peers.isEmpty {
                    List {
                        Section("見つかった端末") {
                            ForEach(model.peers, id: \.self) { peer in
                                Button {
                                    model.invite(peer: peer)
                                } label: {
                                    Label(peer, systemImage: "iphone.radiowaves.left.and.right")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            } else {
                Text("接続を待っています…").font(.headline)
                Text("送信側の端末で「送信する」を開き、この端末を選んでください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verifyStage(code: String, peer: String) -> some View {
        VStack(spacing: 24) {
            Text("確認コード").font(.headline)
            Text(code)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .kerning(8)
                .accessibilityLabel("確認コード \(code.map(String.init).joined(separator: " "))")
            Text("「\(peer)」に同じコードが表示されていることを確認してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button(role: .destructive) {
                    model.reject()
                } label: {
                    Text("拒否").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    model.approve(permissions: permissions, imageOption: appModel.imageOption)
                } label: {
                    Text("一致を確認した").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectingStage: some View {
        VStack(spacing: 0) {
            if model.contacts.isEmpty {
                ProgressView("連絡先を読み込み中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContactSelectionView(contacts: model.contacts, selectedIDs: $model.selectedIDs)
                Button {
                    model.send(imageOption: appModel.imageOption)
                } label: {
                    Text("\(model.selectedIDs.count)件を転送")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedIDs.isEmpty)
                .padding()
            }
        }
    }

    private var receiverCandidatesStage: some View {
        List {
            Section {
                Text("同姓同名の連絡先があります。統合するものを選んでください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("全選択") {
                        model.acceptedCandidateIDs = Set(model.analysis?.candidates.map(\.id) ?? [])
                    }
                    Spacer()
                    Button("全解除") { model.acceptedCandidateIDs = [] }
                }
                .font(.subheadline)
            }
            Section("候補") {
                ForEach(model.analysis?.candidates ?? []) { match in
                    Button {
                        if model.acceptedCandidateIDs.contains(match.id) {
                            model.acceptedCandidateIDs.remove(match.id)
                        } else {
                            model.acceptedCandidateIDs.insert(match.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: model.acceptedCandidateIDs.contains(match.id)
                                  ? "checkmark.circle.fill" : "circle")
                            Text(match.incoming.displayName)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            Section {
                Button {
                    Task { await model.applyPlan() }
                } label: {
                    Text("取り込みを実行").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func failedStage(_ error: AppError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("転送を完了できませんでした").font(.headline)
            Text(error.errorDescription ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("閉じる") {
                model.stop()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
