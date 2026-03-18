import Foundation
import AVFoundation

typealias WhisperResult<T> = Result<T, WhisperError>

enum WhisperError: Error, LocalizedError {
    case contextNotFound
    case modelLoadFailed(String)
    case audioDecodeFailed(String)
    case transcriptionFailed(String)
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .contextNotFound: return "Context not found"
        case .modelLoadFailed(let m): return "Model load failed: \(m)"
        case .audioDecodeFailed(let m): return "Audio decode failed: \(m)"
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        case .notImplemented: return "Not implemented"
        }
    }
}

final class WhisperCpp {

    func initContext(params: [String: Any], modelPath: String, completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let result = WhisperCppBridge.initContext(withModelPath: modelPath, params: params as NSDictionary, error: &error)
            if let error = error {
                completion(.failure(.modelLoadFailed(error.localizedDescription)))
                return
            }
            guard let dict = result as? [String: Any] else {
                completion(.failure(.modelLoadFailed("Invalid response")))
                return
            }
            completion(.success(dict))
        }
    }

    func releaseContext(contextId: Int, completion: @escaping (WhisperResult<Void>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let ok = WhisperCppBridge.releaseContext(NSInteger(contextId), error: &error)
            if let error = error {
                completion(.failure(.transcriptionFailed(error.localizedDescription)))
                return
            }
            completion(ok ? .success(()) : .failure(.contextNotFound))
        }
    }

    func releaseAllContexts(completion: @escaping (WhisperResult<Void>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            WhisperCppBridge.releaseAllContexts()
            completion(.success(()))
        }
    }

    func transcribe(audioData: String, isAudioFile: Bool, params: [String: Any], completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let samples: [Float]
            let contextId: Int
            if let cid = params["contextId"] as? Int {
                contextId = cid
            } else if let cid = params["contextId"] as? NSNumber {
                contextId = cid.intValue
            } else {
                completion(.failure(.transcriptionFailed("contextId required for transcribe")))
                return
            }

            if isAudioFile {
                guard let s = self.loadAudioSamples(fromFile: audioData) else {
                    completion(.failure(.audioDecodeFailed("Could not load audio file")))
                    return
                }
                samples = s
            } else {
                guard let data = Data(base64Encoded: audioData),
                      data.count % MemoryLayout<Float>.size == 0 else {
                    completion(.failure(.audioDecodeFailed("Invalid base64 or length")))
                    return
                }
                samples = data.withUnsafeBytes { buf in
                    Array(UnsafeBufferPointer<Float>(start: buf.bindMemory(to: Float.self).baseAddress, count: data.count / MemoryLayout<Float>.size))
                }
            }

            samples.withUnsafeBufferPointer { buf in
                var error: NSError?
                let result = WhisperCppBridge.transcribe(withContextId: NSInteger(contextId), samples: buf.baseAddress, count: Int32(buf.count), params: params as NSDictionary, error: &error)
                if let error = error {
                    completion(.failure(.transcriptionFailed(error.localizedDescription)))
                    return
                }
                guard let dict = result as? [String: Any] else {
                    completion(.failure(.transcriptionFailed("Invalid response")))
                    return
                }
                completion(.success(dict))
            }
        }
    }

    private func loadAudioSamples(fromFile path: String) -> [Float]? {
        let url: URL
        if path.hasPrefix("/") || path.hasPrefix("file:") {
            url = path.hasPrefix("file:") ? URL(string: path)! : URL(fileURLWithPath: path)
        } else {
            if let bundlePath = Bundle.main.path(forResource: path.replacingOccurrences(of: ".wav", with: "").replacingOccurrences(of: ".mp3", with: ""), ofType: path.hasSuffix(".wav") ? "wav" : "mp3") {
                url = URL(fileURLWithPath: bundlePath)
            } else {
                url = URL(fileURLWithPath: path)
            }
        }
        return loadAudioSamples(from: url)
    }

    private func loadAudioSamples(from url: URL) -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .audio).first!, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ])
        reader.add(output)
        reader.startReading()
        var data = Data()
        while let buf = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buf) {
            var length = 0
            var ptr: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
            if let ptr = ptr, length > 0 {
                data.append(UnsafeBufferPointer(start: ptr, count: length))
            }
        }
        guard data.count >= MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer<Float>(start: buf.bindMemory(to: Float.self).baseAddress, count: data.count / MemoryLayout<Float>.size))
        }
    }

    func transcribeRealtime(params: [String: Any], completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.failure(.notImplemented))
    }

    func stopTranscription(completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.success(()))
    }

    func getSystemInfo(completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = WhisperCppBridge.getSystemInfo()
            completion(.success(info as? [String: Any] ?? [:]))
        }
    }

    func getModelInfo(completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        completion(.failure(.transcriptionFailed("getModelInfo requires contextId; use initContext result")))
    }

    func loadModel(path: String, isAsset: Bool, completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.success(()))
    }

    func unloadModel(completion: @escaping (WhisperResult<Void>) -> Void) {
        WhisperCppBridge.releaseAllContexts()
        completion(.success(()))
    }

    func getAudioFormat(path: String, completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        completion(.failure(.notImplemented))
    }

    func convertAudio(input: String, output: String, targetFormat: [String: Any], completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.failure(.notImplemented))
    }
}
