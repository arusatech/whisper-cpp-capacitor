import Foundation
import Capacitor

@objc(WhisperCppPlugin)
public class WhisperCppPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WhisperCppPlugin"
    public let jsName = "WhisperCpp"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initContext", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "releaseContext", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "releaseAllContexts", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "transcribe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "transcribeRealtime", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopTranscription", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSystemInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getModelInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "unloadModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAudioFormat", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "convertAudio", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addListener", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeAllListeners", returnType: CAPPluginReturnPromise)
    ]

    private let implementation = WhisperCpp()

    @objc func initContext(_ call: CAPPluginCall) {
        guard let params = call.getObject("params"),
              let model = params["model"] as? String else {
            call.reject("model path is required")
            return
        }
        implementation.initContext(params: params, modelPath: model) { result in
            switch result {
            case .success(let context):
                call.resolve(context)
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func releaseContext(_ call: CAPPluginCall) {
        guard let contextId = call.getInt("contextId") else {
            call.reject("contextId is required")
            return
        }
        implementation.releaseContext(contextId: contextId) { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func releaseAllContexts(_ call: CAPPluginCall) {
        implementation.releaseAllContexts { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func transcribe(_ call: CAPPluginCall) {
        guard let params = call.getObject("params"),
              let audioData = call.getString("audio_data") else {
            call.reject("audio_data and params are required")
            return
        }
        let isAudioFile = call.getBool("is_audio_file") ?? false
        var mergedParams = params
        if let cid = call.getInt("contextId") {
            mergedParams["contextId"] = cid
        } else if mergedParams["contextId"] == nil, let cid = params["contextId"] {
            mergedParams["contextId"] = cid
        }
        implementation.transcribe(audioData: audioData, isAudioFile: isAudioFile, params: mergedParams) { result in
            switch result {
            case .success(let transcription):
                call.resolve(transcription)
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func transcribeRealtime(_ call: CAPPluginCall) {
        guard let params = call.getObject("params") else {
            call.reject("params are required")
            return
        }
        implementation.transcribeRealtime(params: params) { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func stopTranscription(_ call: CAPPluginCall) {
        implementation.stopTranscription { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func getSystemInfo(_ call: CAPPluginCall) {
        implementation.getSystemInfo { result in
            switch result {
            case .success(let info):
                call.resolve(info)
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func getModelInfo(_ call: CAPPluginCall) {
        implementation.getModelInfo { result in
            switch result {
            case .success(let info):
                call.resolve(info)
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func loadModel(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }
        let isAsset = call.getBool("is_asset") ?? false
        implementation.loadModel(path: path, isAsset: isAsset) { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func unloadModel(_ call: CAPPluginCall) {
        implementation.unloadModel { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func getAudioFormat(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }
        implementation.getAudioFormat(path: path) { result in
            switch result {
            case .success(let format):
                call.resolve(format)
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func convertAudio(_ call: CAPPluginCall) {
        guard let input = call.getString("input"),
              let output = call.getString("output"),
              let targetFormat = call.getObject("target_format") else {
            call.reject("input, output, and target_format are required")
            return
        }
        implementation.convertAudio(input: input, output: output, targetFormat: targetFormat) { result in
            switch result {
            case .success:
                call.resolve()
            case .failure(let error):
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func addListener(_ call: CAPPluginCall) {
        call.resolve()
    }

    @objc func removeAllListeners(_ call: CAPPluginCall) {
        call.resolve()
    }
}
