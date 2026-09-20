import AVFoundation
import Foundation

/// マイク入力の PCM バッファを SpeechAnalyzer が要求するフォーマットへ変換する。
/// AVAudioEngine のタップ（オーディオスレッド）から直列に呼ばれる前提で、内部の AVAudioConverter を共有する。
nonisolated final class AudioBufferConverter: @unchecked Sendable {
    enum ConversionError: LocalizedError {
        case converterUnavailable
        case bufferAllocationFailed
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .converterUnavailable: "音声フォーマットの変換器を用意できませんでした"
            case .bufferAllocationFailed: "音声バッファを確保できませんでした"
            case .conversionFailed: "音声フォーマットの変換に失敗しました"
            }
        }
    }

    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) throws {
        self.outputFormat = outputFormat
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw ConversionError.converterUnavailable
            }
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter else { return buffer }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw ConversionError.bufferAllocationFailed
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPointer.pointee = .haveData
            return buffer
        }

        if let conversionError { throw conversionError }
        guard status != .error else { throw ConversionError.conversionFailed }
        return output
    }
}
