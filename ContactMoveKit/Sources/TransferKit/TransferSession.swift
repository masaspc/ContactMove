import Foundation
import Models

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

/// MultipeerConnectivity による端末間転送セッション(仕様書 §4)。
/// 暗号化必須(`encryptionPreference: .required`)+ 4桁確認コード照合。
/// delegate コールバックを MainActor へ集約し、UI へは `events`(AsyncStream)で流す。
@MainActor
public final class TransferSession: NSObject, ObservableObject {

    public let events: AsyncStream<TransferEvent>
    @Published public private(set) var discoveredPeers: [String] = []

    static let serviceType = "cntmove"  // Info.plist の _cntmove._tcp と一致
    private static let maxRetriesPerChunk = 3

    private let role: TransferRole
    private let eventContinuation: AsyncStream<TransferEvent>.Continuation
    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var foundPeers: [String: MCPeerID] = [:]
    private var connectedPeer: MCPeerID?
    private var finishedNormally = false

    // 確認コード照合
    private var verificationCode = ""
    private var localApproved = false
    private var remoteApproved = false

    // 送信側の状態
    private var pendingFrames: [Data] = []
    private var frameContactCounts: [Int] = []
    private var currentFrameIndex = 0
    private var retriesForCurrentChunk = 0
    private var sentContacts = 0
    private var totalToSend = 0

    // 受信側の状態
    private var receivedManifest: TransferManifest?
    private var receivedChunks: [Int: [TransferContact]] = [:]
    private var receivedContactCount = 0

    public init(role: TransferRole, deviceName: String) {
        self.role = role
        // MCPeerID displayName は 63 バイト以内
        let name = String(deviceName.prefix(30))
        self.myPeerID = MCPeerID(displayName: name.isEmpty ? "iPhone" : name)
        var continuation: AsyncStream<TransferEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.eventContinuation = continuation
        super.init()
    }

    // MARK: - ライフサイクル

    /// sender: ピア探索(browse)/ receiver: 待受(advertise)を開始する。
    public func start() {
        let session = MCSession(peer: myPeerID, securityIdentity: nil,
                                encryptionPreference: .required)
        session.delegate = self
        self.session = session

        switch role {
        case .sender:
            let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        case .receiver:
            let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil,
                                                       serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        }
    }

    /// 送信側: 発見済みピアへ接続を要求する。
    public func invite(peerNamed name: String) {
        guard let peer = foundPeers[name], let session else { return }
        eventContinuation.yield(.connecting(peer: name))
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    public func approveVerification() {
        localApproved = true
        sendMessage(.verifyApprove)
        checkVerified()
    }

    public func rejectVerification() {
        sendMessage(.verifyReject)
        eventContinuation.yield(.failed(.transferVerificationRejected))
        disconnect()
    }

    /// 送信側: 連絡先を送る(確認コード承認後に呼ぶ)。
    public func send(contacts: [TransferContact], includesPhotos: Bool) async {
        guard role == .sender else { return }
        do {
            let frames = try ChunkCodec.makeFrames(contacts: contacts)
            pendingFrames = frames
            frameContactCounts = stride(from: 0, to: contacts.count,
                                        by: ContactChunk.maxContactsPerChunk)
                .map { min(ContactChunk.maxContactsPerChunk, contacts.count - $0) }
            currentFrameIndex = 0
            retriesForCurrentChunk = 0
            sentContacts = 0
            totalToSend = contacts.count

            let manifest = TransferManifest(
                deviceName: myPeerID.displayName,
                totalCount: contacts.count,
                totalBytes: frames.reduce(0) { $0 + $1.count },
                includesPhotos: includesPhotos,
                chunkCount: frames.count)
            sendMessage(.manifest(manifest))

            if frames.isEmpty {
                // 0件送信: 即完了扱い(受信側は contactsReceived([]) を出す)
                eventContinuation.yield(.progress(done: 0, total: 0))
            } else {
                sendCurrentFrame()
            }
        } catch {
            eventContinuation.yield(.failed(.transferConnectionLost))
            disconnect()
        }
    }

    /// 受信側: 取り込み完了後の最終結果を送信側へ返す。
    public func sendResult(_ result: TransferResult) async {
        sendMessage(.result(result))
        finishedNormally = true
        eventContinuation.yield(.finished)
    }

    public func cancel() {
        sendMessage(.cancel)
        eventContinuation.yield(.failed(.cancelled(completedCount: 0)))
        disconnect()
    }

    public func stop() {
        finishedNormally = true
        disconnect()
        eventContinuation.finish()
    }

    private func disconnect() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        connectedPeer = nil
    }

    // MARK: - 送信ヘルパー

    private func sendMessage(_ message: TransferMessage) {
        guard let session, let peer = connectedPeer else { return }
        do {
            try session.send(try message.encode(), toPeers: [peer], with: .reliable)
        } catch {
            handleConnectionLost()
        }
    }

    private func sendCurrentFrame() {
        guard currentFrameIndex < pendingFrames.count else { return }
        sendMessage(.chunkFrame(pendingFrames[currentFrameIndex]))
    }

    private func checkVerified() {
        if localApproved && remoteApproved {
            eventContinuation.yield(.verified)
        }
    }

    private func handleConnectionLost() {
        guard !finishedNormally else { return }
        finishedNormally = true
        eventContinuation.yield(.failed(.transferConnectionLost))
        disconnect()
    }

    // MARK: - 受信メッセージ処理(MainActor 上で実行)

    private func handle(message: TransferMessage, from peer: MCPeerID) {
        switch message {
        case .hello(let hello):
            // 受信側: バージョン照合 → 確認コード表示
            guard hello.protocolVersion == TransferManifest.currentProtocolVersion else {
                sendMessage(.verifyReject)
                eventContinuation.yield(
                    .failed(.transferProtocolMismatch(remoteVersion: hello.protocolVersion)))
                disconnect()
                return
            }
            verificationCode = hello.verificationCode
            eventContinuation.yield(
                .verificationRequired(code: hello.verificationCode, peer: peer.displayName))

        case .verifyApprove:
            remoteApproved = true
            checkVerified()

        case .verifyReject:
            eventContinuation.yield(.failed(.transferVerificationRejected))
            disconnect()

        case .manifest(let manifest):
            receivedManifest = manifest
            receivedChunks = [:]
            receivedContactCount = 0
            eventContinuation.yield(.manifestReceived(manifest))
            if manifest.chunkCount == 0 {
                eventContinuation.yield(.contactsReceived([]))
            }

        case .chunkFrame(let frame):
            handleChunkFrame(frame)

        case .ack(let ack):
            handleAck(ack)

        case .result(let result):
            eventContinuation.yield(.resultReceived(result))
            finishedNormally = true
            eventContinuation.yield(.finished)
            disconnect()

        case .cancel:
            finishedNormally = true
            eventContinuation.yield(.failed(.cancelled(completedCount: receivedContactCount)))
            disconnect()
        }
    }

    private func handleChunkFrame(_ frame: Data) {
        do {
            let chunk = try ChunkCodec.decodeFrame(frame)
            if receivedChunks[chunk.index] == nil {
                receivedChunks[chunk.index] = chunk.contacts
                receivedContactCount += chunk.contacts.count
            }
            sendMessage(.ack(ChunkAck(index: chunk.index, ok: true)))
            let total = receivedManifest?.totalCount ?? receivedContactCount
            eventContinuation.yield(.progress(done: receivedContactCount, total: total))

            if let manifest = receivedManifest, receivedChunks.count == manifest.chunkCount {
                let all = receivedChunks.sorted { $0.key < $1.key }.flatMap(\.value)
                eventContinuation.yield(.contactsReceived(all))
            }
        } catch {
            // チェックサム不一致等 → 再送要求
            let index = (try? ChunkCodec.decodeFrame(frame).index) ?? currentFrameIndexFromHeader(frame)
            sendMessage(.ack(ChunkAck(index: index, ok: false)))
        }
    }

    /// 破損フレームからでもヘッダの index だけは取り出せる場合があるため試みる。
    private func currentFrameIndexFromHeader(_ frame: Data) -> Int {
        let bytes = Data(frame)
        guard bytes.count >= 5 else { return -1 }
        let headerLength = Int(UInt32(bigEndian: bytes.subdata(in: 1..<5).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }))
        guard bytes.count >= 5 + headerLength,
              let header = try? JSONDecoder().decode(
                ChunkCodec.FrameHeader.self, from: bytes.subdata(in: 5..<(5 + headerLength)))
        else { return -1 }
        return header.index
    }

    private func handleAck(_ ack: ChunkAck) {
        guard role == .sender, currentFrameIndex < pendingFrames.count,
              ack.index == currentFrameIndex else { return }
        if ack.ok {
            sentContacts += frameContactCounts[currentFrameIndex]
            eventContinuation.yield(.progress(done: sentContacts, total: totalToSend))
            currentFrameIndex += 1
            retriesForCurrentChunk = 0
            if currentFrameIndex < pendingFrames.count {
                sendCurrentFrame()
            }
            // 全チャンク送信完了後は受信側の result を待つ
        } else {
            retriesForCurrentChunk += 1
            if retriesForCurrentChunk > Self.maxRetriesPerChunk {
                eventContinuation.yield(.failed(.transferChecksumFailed(chunkIndex: ack.index)))
                sendMessage(.cancel)
                disconnect()
            } else {
                sendCurrentFrame()
            }
        }
    }

    private func handlePeerStateChange(_ peer: MCPeerID, state: MCSessionState) {
        switch state {
        case .connecting:
            eventContinuation.yield(.connecting(peer: peer.displayName))
        case .connected:
            connectedPeer = peer
            if role == .sender {
                // 接続直後に挨拶(バージョン+確認コード)を送り、双方に表示
                verificationCode = ChunkCodec.makeVerificationCode()
                sendMessage(.hello(.init(
                    protocolVersion: TransferManifest.currentProtocolVersion,
                    deviceName: myPeerID.displayName,
                    verificationCode: verificationCode)))
                eventContinuation.yield(
                    .verificationRequired(code: verificationCode, peer: peer.displayName))
            }
        case .notConnected:
            if connectedPeer == peer {
                handleConnectionLost()
            }
        @unknown default:
            break
        }
    }
}

// MARK: - MCSessionDelegate

extension TransferSession: MCSessionDelegate {
    nonisolated public func session(_ session: MCSession, peer peerID: MCPeerID,
                                    didChange state: MCSessionState) {
        Task { @MainActor in
            self.handlePeerStateChange(peerID, state: state)
        }
    }

    nonisolated public func session(_ session: MCSession, didReceive data: Data,
                                    fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let message = try? TransferMessage.decode(data) else { return }
            self.handle(message: message, from: peerID)
        }
    }

    nonisolated public func session(_ session: MCSession, didReceive stream: InputStream,
                                    withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                                    fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                                    fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate(送信側)

extension TransferSession: MCNearbyServiceBrowserDelegate {
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                                    withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.foundPeers[peerID.displayName] = peerID
            self.discoveredPeers = Array(self.foundPeers.keys).sorted()
            self.eventContinuation.yield(.peersChanged(self.discoveredPeers))
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.foundPeers.removeValue(forKey: peerID.displayName)
            self.discoveredPeers = Array(self.foundPeers.keys).sorted()
            self.eventContinuation.yield(.peersChanged(self.discoveredPeers))
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate(受信側)

extension TransferSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                       didReceiveInvitationFromPeer peerID: MCPeerID,
                                       withContext context: Data?,
                                       invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // 接続自体は自動承諾し、その後アプリ層の確認コード照合で防御する
            invitationHandler(true, self.session)
            self.eventContinuation.yield(.connecting(peer: peerID.displayName))
        }
    }
}

#else

/// MultipeerConnectivity が使えない環境(Linux 等)向けのスタブ。
/// API 互換性のためだけに存在し、start() は即座に失敗イベントを流す。
@MainActor
public final class TransferSession: ObservableObject {
    public let events: AsyncStream<TransferEvent>
    @Published public private(set) var discoveredPeers: [String] = []
    private let eventContinuation: AsyncStream<TransferEvent>.Continuation

    public init(role: TransferRole, deviceName: String) {
        var continuation: AsyncStream<TransferEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func start() {
        eventContinuation.yield(.failed(.transferConnectionLost))
    }

    public func invite(peerNamed name: String) {}
    public func approveVerification() {}
    public func rejectVerification() {}
    public func send(contacts: [TransferContact], includesPhotos: Bool) async {}
    public func sendResult(_ result: TransferResult) async {}
    public func cancel() {}
    public func stop() {
        eventContinuation.finish()
    }
}

#endif
