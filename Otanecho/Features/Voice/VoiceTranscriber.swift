import AVFoundation
import Foundation
import Observation
import Speech

/// iOS 26 の `SpeechAnalyzer` + `SpeechTranscriber` でマイク入力を日本語に文字起こしする。
/// 確定した結果は `onFinalText` で通知し、途中結果は `volatileText` に流す。
@MainActor
@Observable
final class VoiceTranscriber {
    enum Permission: Equatable {
        /// まだ確認していない・未要求
        case unknown
        case authorized
        case denied
    }

    enum VoiceError: LocalizedError {
        case permissionDenied
        case transcriberUnavailable
        case localeUnsupported
        case audioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "マイクと音声認識の許可が必要です"
            case .transcriberUnavailable: "この端末では音声認識を利用できません"
            case .localeUnsupported: "日本語の音声認識モデルを利用できません"
            case .audioFormatUnavailable: "音声認識に使えるオーディオ形式が見つかりません"
            }
        }
    }

    private(set) var permission: Permission = .unknown
    private(set) var isRecording = false
    /// モデル確保・エンジン起動中
    private(set) var isPreparing = false
    /// まだ確定していない途中結果
    private(set) var volatileText = ""
    var errorMessage: String?

    /// 確定した文字列が届いたときに呼ばれる。binding にはこの確定分だけを書く。
    var onFinalText: ((String) -> Void)?

    private let locale = Locale(identifier: "ja-JP")
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // MARK: - 権限

    /// ダイアログを出さずに現在の許可状態を反映する。
    func refreshPermission() {
        let microphone = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        switch (microphone, speech) {
        case (.granted, .authorized):
            permission = .authorized
        case (.denied, _), (_, .denied), (_, .restricted):
            permission = .denied
        default:
            permission = .unknown
        }
    }

    /// マイクと音声認識の許可を求める。
    @discardableResult
    func requestPermission() async -> Bool {
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        permission = (microphoneGranted && speechStatus == .authorized) ? .authorized : .denied
        return permission == .authorized
    }

    // MARK: - 録音の開始・停止

    func toggle() async {
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard !isRecording, !isPreparing else { return }
        errorMessage = nil

        if permission != .authorized {
            guard await requestPermission() else {
                errorMessage = VoiceError.permissionDenied.localizedDescription
                return
            }
        }

        isPreparing = true
        defer { isPreparing = false }
        do {
            try await startAnalysis()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            await tearDown(cancelling: true)
        }
    }

    func stop() async {
        guard isRecording else { return }
        isRecording = false
        await tearDown(cancelling: false)
    }

    // MARK: - 内部処理

    private func startAnalysis() async throws {
        guard SpeechTranscriber.isAvailable else { throw VoiceError.transcriberUnavailable }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw VoiceError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await ensureModel(for: transcriber, locale: supportedLocale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.audioFormatUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = try AudioBufferConverter(from: inputFormat, to: analyzerFormat)
        let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = try? converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
        try await analyzer.start(inputSequence: inputStream)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.audioEngine = engine
        self.inputContinuation = continuation
        self.volatileText = ""

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        volatileText = ""
                        if !text.isEmpty { onFinalText?(text) }
                    } else {
                        volatileText = text
                    }
                }
            } catch {
                self?.errorMessage = "音声認識でエラー: \(error.localizedDescription)"
            }
        }
    }

    /// 日本語モデルが端末にあることを保証する。なければダウンロードして待つ。
    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        // 予約枠の上限などで失敗しても、インストール自体は続行できる
        _ = try? await AssetInventory.reserve(locale: locale)

        if !isInstalled, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// 入力を止め、認識を終わらせてリソースを解放する。
    /// - Parameter cancelling: true なら未処理の音声を捨てて即終了、false なら最後まで認識してから終了する。
    private func tearDown(cancelling: Bool) async {
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        inputContinuation?.finish()

        if let analyzer {
            if cancelling {
                await analyzer.cancelAndFinishNow()
            } else {
                do {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                } catch {
                    errorMessage = "音声認識の終了に失敗: \(error.localizedDescription)"
                }
            }
        }
        await resultsTask?.value

        resultsTask = nil
        inputContinuation = nil
        audioEngine = nil
        analyzer = nil
        transcriber = nil
        volatileText = ""

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
