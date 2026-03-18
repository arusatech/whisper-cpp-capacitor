import Foundation
import AVFoundation

typealias WhisperResult<T> = Result<T, WhisperError>

enum WhisperError: Error, LocalizedError {
    case contextNotFound
    case modelLoadFailed(String)
    case audioDecodeFailed(String)
    case transcriptionFailed(String)
    case notImplemented
    case streamingSessionActive
    case noActiveSession
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .contextNotFound: return "Context not found"
        case .modelLoadFailed(let m): return "Model load failed: \(m)"
        case .audioDecodeFailed(let m): return "Audio decode failed: \(m)"
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        case .notImplemented: return "Not implemented"
        case .streamingSessionActive: return "A streaming session is already active"
        case .noActiveSession: return "No active streaming session"
        case .microphonePermissionDenied: return "Microphone permission denied"
        }
    }
}

/// Manages state for a single real-time streaming transcription session.
final class StreamingSession {
    let contextId: Int
    let chunkLengthMs: Int
    let stepLengthMs: Int
    let params: [String: Any]
    let onSegment: ([String: Any]) -> Void
    let onResult: ([String: Any]) -> Void
    let onError: (String) -> Void

    private let audioEngine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "com.whisper.streaming", qos: .userInitiated)
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var isActive = false
    private var allSegments: [[String: Any]] = []
    private var fullText = ""
    private var lastEndTime: Double = 0
    private var totalSamplesProcessed: Int = 0
    private let sampleRate: Double = 16000

    init(contextId: Int, chunkLengthMs: Int, stepLengthMs: Int, params: [String: Any],
         onSegment: @escaping ([String: Any]) -> Void,
         onResult: @escaping ([String: Any]) -> Void,
         onError: @escaping (String) -> Void) {
        self.contextId = contextId
        self.chunkLengthMs = chunkLengthMs
        self.stepLengthMs = stepLengthMs
        self.params = params
        self.onSegment = onSegment
        self.onResult = onResult
        self.onError = onError
    }

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        isActive = true

        // Install tap - use hardware format and convert in the callback
        let tapFormat = hardwareFormat.sampleRate == sampleRate && hardwareFormat.channelCount == 1
            ? desiredFormat
            : hardwareFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self, self.isActive else { return }
            self.handleAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Schedule periodic chunk processing
        scheduleChunkProcessing()
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        // Take only the first channel (mono or first of multi-channel)
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = floatData[0][i]
        }

        // If sample rate differs from 16kHz, do simple linear resampling
        let sourceSampleRate = buffer.format.sampleRate
        if sourceSampleRate != sampleRate {
            samples = resample(samples, from: sourceSampleRate, to: sampleRate)
        }

        bufferLock.lock()
        sampleBuffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    private func resample(_ input: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let outputCount = Int(Double(input.count) * ratio)
        guard outputCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIdx = Double(i) / ratio
            let idx0 = Int(srcIdx)
            let frac = Float(srcIdx - Double(idx0))
            let idx1 = min(idx0 + 1, input.count - 1)
            if idx0 < input.count {
                output[i] = input[idx0] * (1 - frac) + input[min(idx1, input.count - 1)] * frac
            }
        }
        return output
    }

    private func scheduleChunkProcessing() {
        let chunkSamples = Int(sampleRate * Double(chunkLengthMs) / 1000.0)

        processingQueue.async { [weak self] in
            while let self = self, self.isActive {
                self.bufferLock.lock()
                let currentCount = self.sampleBuffer.count
                self.bufferLock.unlock()

                if currentCount >= chunkSamples {
                    self.processChunk(chunkSamples: chunkSamples)
                } else {
                    // Wait a bit before checking again
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
    }

    private func processChunk(chunkSamples: Int) {
        let stepSamples = Int(sampleRate * Double(stepLengthMs) / 1000.0)

        bufferLock.lock()
        guard sampleBuffer.count >= chunkSamples else {
            bufferLock.unlock()
            return
        }
        // Take chunkSamples worth of audio
        let chunk = Array(sampleBuffer.prefix(chunkSamples))
        // Slide the window: keep the last stepSamples for overlap context
        let removeCount = max(chunkSamples - stepSamples, 0)
        if removeCount > 0 && removeCount <= sampleBuffer.count {
            sampleBuffer.removeFirst(removeCount)
        }
        bufferLock.unlock()

        // Calculate the time offset for this chunk based on total samples processed
        let chunkOffsetMs = Int(Double(totalSamplesProcessed) / sampleRate * 1000.0)
        totalSamplesProcessed += max(chunkSamples - stepSamples, 0)

        // Run transcription via the bridge
        var transcribeParams = params
        transcribeParams["contextId"] = contextId

        chunk.withUnsafeBufferPointer { buf in
            var error: NSError?
            let result = WhisperCppBridge.transcribe(
                withContextId: NSInteger(contextId),
                samples: buf.baseAddress,
                count: Int32(buf.count),
                params: transcribeParams as NSDictionary,
                error: &error
            )

            if let error = error {
                self.onError(error.localizedDescription)
                return
            }

            guard let dict = result as? [String: Any],
                  let segments = dict["segments"] as? [[String: Any]] else {
                return
            }

            for segment in segments {
                guard var seg = segment as? [String: Any] else { continue }
                // Adjust segment times relative to the overall stream
                if let start = seg["start"] as? NSNumber {
                    seg["start"] = NSNumber(value: start.doubleValue + Double(chunkOffsetMs))
                }
                if let end = seg["end"] as? NSNumber {
                    seg["end"] = NSNumber(value: end.doubleValue + Double(chunkOffsetMs))
                }

                // Ensure monotonic: start >= last end
                let segStart = (seg["start"] as? NSNumber)?.doubleValue ?? 0
                if segStart < self.lastEndTime {
                    seg["start"] = NSNumber(value: self.lastEndTime)
                }
                let segEnd = (seg["end"] as? NSNumber)?.doubleValue ?? 0
                if segEnd < (seg["start"] as? NSNumber)?.doubleValue ?? 0 {
                    seg["end"] = seg["start"]
                }
                self.lastEndTime = (seg["end"] as? NSNumber)?.doubleValue ?? self.lastEndTime

                if let text = seg["text"] as? String {
                    self.fullText += text
                }
                self.allSegments.append(seg)
                self.onSegment(seg)
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false

        // Stop audio capture
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Process any remaining buffered audio
        bufferLock.lock()
        let remaining = sampleBuffer
        sampleBuffer.removeAll()
        bufferLock.unlock()

        if !remaining.isEmpty {
            processRemainingAudio(remaining)
        }

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // Emit final result
        let totalDurationMs = Double(totalSamplesProcessed) / sampleRate * 1000.0
        let finalResult: [String: Any] = [
            "text": fullText,
            "segments": allSegments,
            "words": [] as [[String: Any]],
            "language": (params["language"] as? String) ?? "en",
            "language_prob": 1.0,
            "duration_ms": totalDurationMs,
            "processing_time_ms": 0
        ]
        onResult(finalResult)
    }

    private func processRemainingAudio(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let chunkOffsetMs = Int(Double(totalSamplesProcessed) / sampleRate * 1000.0)
        totalSamplesProcessed += samples.count

        var transcribeParams = params
        transcribeParams["contextId"] = contextId

        samples.withUnsafeBufferPointer { buf in
            var error: NSError?
            let result = WhisperCppBridge.transcribe(
                withContextId: NSInteger(contextId),
                samples: buf.baseAddress,
                count: Int32(buf.count),
                params: transcribeParams as NSDictionary,
                error: &error
            )

            guard error == nil,
                  let dict = result as? [String: Any],
                  let segments = dict["segments"] as? [[String: Any]] else {
                return
            }

            for segment in segments {
                guard var seg = segment as? [String: Any] else { continue }
                if let start = seg["start"] as? NSNumber {
                    seg["start"] = NSNumber(value: start.doubleValue + Double(chunkOffsetMs))
                }
                if let end = seg["end"] as? NSNumber {
                    seg["end"] = NSNumber(value: end.doubleValue + Double(chunkOffsetMs))
                }
                let segStart = (seg["start"] as? NSNumber)?.doubleValue ?? 0
                if segStart < self.lastEndTime {
                    seg["start"] = NSNumber(value: self.lastEndTime)
                }
                let segEnd = (seg["end"] as? NSNumber)?.doubleValue ?? 0
                if segEnd < (seg["start"] as? NSNumber)?.doubleValue ?? 0 {
                    seg["end"] = seg["start"]
                }
                self.lastEndTime = (seg["end"] as? NSNumber)?.doubleValue ?? self.lastEndTime

                if let text = seg["text"] as? String {
                    self.fullText += text
                }
                self.allSegments.append(seg)
                // Don't emit segment events during stop - only the final result
            }
        }
    }

    var active: Bool { isActive }
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

    private(set) var activeSession: StreamingSession?
    private let sessionLock = NSLock()

    /// Callback closures set by the plugin layer for event emission.
    var onSegment: (([String: Any]) -> Void)?
    var onResult: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?

    func transcribeRealtime(params: [String: Any], completion: @escaping (WhisperResult<Void>) -> Void) {
        sessionLock.lock()
        if activeSession != nil {
            sessionLock.unlock()
            completion(.failure(.streamingSessionActive))
            return
        }
        sessionLock.unlock()

        // Extract contextId
        let contextId: Int
        if let cid = params["contextId"] as? Int {
            contextId = cid
        } else if let cid = params["contextId"] as? NSNumber {
            contextId = cid.intValue
        } else {
            completion(.failure(.transcriptionFailed("contextId required for transcribeRealtime")))
            return
        }

        let chunkLengthMs = (params["chunk_length_ms"] as? Int) ?? 3000
        let stepLengthMs = (params["step_length_ms"] as? Int) ?? 500

        // Check microphone permission
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            break
        case .denied:
            completion(.failure(.microphonePermissionDenied))
            return
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    self?.startStreamingSession(contextId: contextId, chunkLengthMs: chunkLengthMs, stepLengthMs: stepLengthMs, params: params, completion: completion)
                } else {
                    completion(.failure(.microphonePermissionDenied))
                }
            }
            return
        @unknown default:
            completion(.failure(.microphonePermissionDenied))
            return
        }

        startStreamingSession(contextId: contextId, chunkLengthMs: chunkLengthMs, stepLengthMs: stepLengthMs, params: params, completion: completion)
    }

    private func startStreamingSession(contextId: Int, chunkLengthMs: Int, stepLengthMs: Int, params: [String: Any], completion: @escaping (WhisperResult<Void>) -> Void) {
        let session = StreamingSession(
            contextId: contextId,
            chunkLengthMs: chunkLengthMs,
            stepLengthMs: stepLengthMs,
            params: params,
            onSegment: { [weak self] segment in
                self?.onSegment?(segment)
            },
            onResult: { [weak self] result in
                self?.onResult?(result)
                self?.sessionLock.lock()
                self?.activeSession = nil
                self?.sessionLock.unlock()
            },
            onError: { [weak self] message in
                self?.onError?(message)
            }
        )

        sessionLock.lock()
        // Double-check no session was started in the meantime
        if activeSession != nil {
            sessionLock.unlock()
            completion(.failure(.streamingSessionActive))
            return
        }
        activeSession = session
        sessionLock.unlock()

        do {
            try session.start()
            completion(.success(()))
        } catch {
            sessionLock.lock()
            activeSession = nil
            sessionLock.unlock()
            completion(.failure(.transcriptionFailed("Failed to start audio engine: \(error.localizedDescription)")))
        }
    }

    func stopTranscription(completion: @escaping (WhisperResult<Void>) -> Void) {
        sessionLock.lock()
        guard let session = activeSession else {
            sessionLock.unlock()
            completion(.success(()))
            return
        }
        sessionLock.unlock()

        session.stop()
        // activeSession is cleared in the onResult callback
        completion(.success(()))
    }

    func getSystemInfo(completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = WhisperCppBridge.getSystemInfo()
            completion(.success(info as? [String: Any] ?? [:]))
        }
    }

    func getModelInfo(contextId: Int, completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let result = WhisperCppBridge.getModelInfo(forContextId: NSInteger(contextId), error: &error)
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

    func loadModel(path: String, isAsset: Bool, completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.success(()))
    }

    func unloadModel(completion: @escaping (WhisperResult<Void>) -> Void) {
        WhisperCppBridge.releaseAllContexts()
        completion(.success(()))
    }

    func getAudioFormat(path: String, completion: @escaping (WhisperResult<[String: Any]>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url: URL
            if path.hasPrefix("/") || path.hasPrefix("file:") {
                url = path.hasPrefix("file:") ? URL(string: path)! : URL(fileURLWithPath: path)
            } else {
                url = URL(fileURLWithPath: path)
            }

            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .audio).first else {
                completion(.failure(.audioDecodeFailed("No audio track found")))
                return
            }

            let descriptions = track.formatDescriptions as! [CMAudioFormatDescription]
            guard let desc = descriptions.first else {
                completion(.failure(.audioDecodeFailed("No format description")))
                return
            }

            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
            let sampleRate = Int(asbd?.mSampleRate ?? 0)
            let channels = Int(asbd?.mChannelsPerFrame ?? 0)
            let bitsPerSample = Int(asbd?.mBitsPerChannel ?? 0)

            // Determine format from file extension
            let ext = url.pathExtension.lowercased()
            let format: String
            switch ext {
            case "wav": format = "wav"
            case "mp3": format = "mp3"
            case "ogg": format = "ogg"
            case "flac": format = "flac"
            case "m4a", "aac": format = "m4a"
            case "webm": format = "webm"
            default: format = ext.isEmpty ? "wav" : ext
            }

            let result: [String: Any] = [
                "sample_rate": sampleRate,
                "channels": channels,
                "bits_per_sample": bitsPerSample,
                "format": format
            ]
            completion(.success(result))
        }
    }

    func convertAudio(input: String, output: String, targetFormat: [String: Any], completion: @escaping (WhisperResult<Void>) -> Void) {
        completion(.failure(.notImplemented))
    }
}
