#include <jni.h>
#include <string>
#include <sstream>
#include <map>
#include <android/log.h>
#include "cap-whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

static std::map<int, cap_whisper_context*> s_contexts;
static int s_nextId = 1;

static std::string escapeJson(const char* s) {
    if (!s) return "\"\"";
    std::string o = "\"";
    for (; *s; s++) {
        if (*s == '"') o += "\\\"";
        else if (*s == '\\') o += "\\\\";
        else if (*s == '\n') o += "\\n";
        else o += *s;
    }
    o += "\"";
    return o;
}

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_initContext(
    JNIEnv* env, jclass, jstring jModelPath, jstring jParamsJson) {
    (void)jParamsJson;
    const char* path = env->GetStringUTFChars(jModelPath, nullptr);
    if (!path) return env->NewStringUTF("{}");
    cap_whisper_context_params params = {};
    params.model_path = path;
    params.use_gpu = false;
    params.n_threads = 4;
    params.n_max_text_ctx = 16384;
    params.detect_language = true;
    bool useGpu = false;
    char reasonBuf[256] = {0};
    cap_whisper_context* ctx = cap_whisper_init(path, &params, &useGpu, reasonBuf, sizeof(reasonBuf));
    env->ReleaseStringUTFChars(jModelPath, path);
    if (!ctx) return env->NewStringUTF("{}");
    int id = s_nextId++;
    s_contexts[id] = ctx;
    cap_whisper_model_info info = {};
    if (cap_whisper_get_model_info(ctx, &info) != 0) {
        cap_whisper_free(ctx);
        s_contexts.erase(id);
        return env->NewStringUTF("{}");
    }
    std::ostringstream out;
    out << "{\"contextId\":" << id
        << ",\"model\":{\"type\":" << escapeJson(info.type)
        << ",\"is_multilingual\":" << (info.is_multilingual ? "true" : "false")
        << ",\"vocab_size\":" << info.vocab_size
        << ",\"n_audio_ctx\":" << info.n_audio_ctx
        << ",\"n_audio_state\":" << info.n_audio_state
        << ",\"n_audio_head\":" << info.n_audio_head
        << ",\"n_audio_layer\":" << info.n_audio_layer
        << ",\"n_text_ctx\":" << info.n_text_ctx
        << ",\"n_text_state\":" << info.n_text_state
        << ",\"n_text_head\":" << info.n_text_head
        << ",\"n_text_layer\":" << info.n_text_layer
        << ",\"n_mels\":" << info.n_mels
        << ",\"ftype\":" << info.ftype << "}"
        << ",\"gpu\":" << (useGpu ? "true" : "false")
        << ",\"reasonNoGPU\":" << escapeJson(reasonBuf) << "}";
    cap_whisper_model_info_free(&info);
    return env->NewStringUTF(out.str().c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_releaseContext(
    JNIEnv*, jclass, jint contextId) {
    auto it = s_contexts.find(contextId);
    if (it == s_contexts.end()) return JNI_FALSE;
    cap_whisper_free(it->second);
    s_contexts.erase(it);
    return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_releaseAllContexts(
    JNIEnv*, jclass) {
    for (auto& p : s_contexts) cap_whisper_free(p.second);
    s_contexts.clear();
}

JNIEXPORT jstring JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_transcribe(
    JNIEnv* env, jclass, jint contextId, jstring jAudioData, jboolean isAudioFile, jstring jParamsJson) {
    (void)jParamsJson;
    if (s_contexts.find(contextId) == s_contexts.end()) return env->NewStringUTF("{}");
    cap_whisper_context* ctx = s_contexts[contextId];
    const char* dataStr = env->GetStringUTFChars(jAudioData, nullptr);
    if (!dataStr) return env->NewStringUTF("{}");
    std::vector<float> samples;
    if (isAudioFile == JNI_TRUE) {
        FILE* f = fopen(dataStr, "rb");
        env->ReleaseStringUTFChars(jAudioData, dataStr);
        if (!f) return env->NewStringUTF("{}");
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size > 0 && size <= 100*1024*1024) {
            std::vector<char> buf(size);
            if (fread(buf.data(), 1, size, f) == (size_t)size) {
                size_t n = size / sizeof(float);
                samples.resize(n);
                memcpy(samples.data(), buf.data(), size);
            }
        }
        fclose(f);
    } else {
        std::string b64(dataStr);
        env->ReleaseStringUTFChars(jAudioData, dataStr);
        if (b64.empty()) return env->NewStringUTF("{}");
        size_t decLen = (b64.size() * 3) / 4;
        std::vector<unsigned char> dec(decLen);
        const char* tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        size_t i = 0, j = 0;
        int val = 0, pad = 0;
        for (char c : b64) {
            if (c == '=') { pad++; continue; }
            const char* p = strchr(tbl, c);
            if (!p) continue;
            val = (val << 6) | (p - tbl);
            if (++i % 4 == 0) {
                if (j < decLen) dec[j++] = (val >> 16) & 0xff;
                if (j < decLen) dec[j++] = (val >> 8) & 0xff;
                if (j < decLen) dec[j++] = val & 0xff;
            }
        }
        size_t n = j / sizeof(float);
        samples.resize(n);
        memcpy(samples.data(), dec.data(), n * sizeof(float));
    }
    if (samples.empty()) return env->NewStringUTF("{}");
    cap_whisper_full_params* fp = cap_whisper_full_params_default();
    cap_whisper_result result = {};
    int ret = cap_whisper_full(ctx, samples.data(), (int)samples.size(), fp, &result);
    cap_whisper_full_params_free(fp);
    if (ret != 0) {
        return env->NewStringUTF("{}");
    }
    std::ostringstream out;
    out << "{\"text\":" << escapeJson(result.text)
        << ",\"language\":" << escapeJson(result.language)
        << ",\"language_prob\":" << result.language_prob
        << ",\"duration_ms\":" << result.duration_ms
        << ",\"processing_time_ms\":" << result.processing_time_ms
        << ",\"segments\":[";
    for (int i = 0; i < result.n_segments; i++) {
        if (i) out << ",";
        out << "{\"start\":" << result.segments[i].start_ms
            << ",\"end\":" << result.segments[i].end_ms
            << ",\"text\":" << escapeJson(result.segments[i].text)
            << ",\"no_speech_prob\":" << result.segments[i].no_speech_prob
            << ",\"speaker_id\":" << result.segments[i].speaker_id << "}";
    }
    out << "]}";
    cap_whisper_result_free(&result);
    return env->NewStringUTF(out.str().c_str());
}

JNIEXPORT jstring JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_getSystemInfo(
    JNIEnv* env, jclass) {
    std::string json = "{\"platform\":\"android\",\"gpu_available\":false,\"max_threads\":4,\"memory_available_mb\":0}";
    return env->NewStringUTF(json.c_str());
}

} // extern "C"
