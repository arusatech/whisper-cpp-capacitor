#include <jni.h>
#include <string>
#include <sstream>
#include <map>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <android/log.h>
#include <sys/sysinfo.h>
#include <unistd.h>
#include "cap-whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

// ---------------------------------------------------------------------------
// Minimal JSON helpers – no external dependencies.
// These work on the flat JSON objects produced by JSObject.toString().
// ---------------------------------------------------------------------------

// Find the value substring for a given key in a JSON object string.
// Returns empty string if not found.
static std::string jsonGetRaw(const std::string& json, const char* key) {
    std::string needle = std::string("\"") + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return "";
    pos += needle.size();
    // skip whitespace
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' || json[pos] == '\r')) pos++;
    if (pos >= json.size() || json[pos] != ':') return "";
    pos++; // skip ':'
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' || json[pos] == '\r')) pos++;
    if (pos >= json.size()) return "";

    if (json[pos] == '"') {
        // string value
        pos++; // skip opening quote
        std::string result;
        while (pos < json.size() && json[pos] != '"') {
            if (json[pos] == '\\' && pos + 1 < json.size()) {
                pos++;
                if (json[pos] == '"') result += '"';
                else if (json[pos] == '\\') result += '\\';
                else if (json[pos] == 'n') result += '\n';
                else result += json[pos];
            } else {
                result += json[pos];
            }
            pos++;
        }
        return result;
    }
    // non-string value (number, bool, null) – read until delimiter
    size_t start = pos;
    while (pos < json.size() && json[pos] != ',' && json[pos] != '}' && json[pos] != ' ' && json[pos] != '\n') pos++;
    return json.substr(start, pos - start);
}

static bool jsonGetBool(const std::string& json, const char* key, bool defaultVal) {
    std::string v = jsonGetRaw(json, key);
    if (v.empty()) return defaultVal;
    return (v == "true" || v == "1");
}

static int jsonGetInt(const std::string& json, const char* key, int defaultVal) {
    std::string v = jsonGetRaw(json, key);
    if (v.empty() || v == "null") return defaultVal;
    return atoi(v.c_str());
}

static float jsonGetFloat(const std::string& json, const char* key, float defaultVal) {
    std::string v = jsonGetRaw(json, key);
    if (v.empty() || v == "null") return defaultVal;
    return (float)atof(v.c_str());
}

// Returns the string value for a key, or empty string if absent/null.
static std::string jsonGetString(const std::string& json, const char* key) {
    std::string raw = jsonGetRaw(json, key);
    if (raw == "null") return "";
    return raw;
}

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

// ---------------------------------------------------------------------------
// WAV audio file loader with format conversion.
// Parses RIFF/WAVE headers, extracts PCM data, converts to 16kHz mono float32.
// Falls back to raw float32 if the file is not a WAV.
// ---------------------------------------------------------------------------
static bool loadAudioFile(const char* path, std::vector<float>& samples) {
    FILE* f = fopen(path, "rb");
    if (!f) return false;

    fseek(f, 0, SEEK_END);
    long fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (fileSize <= 0 || fileSize > 100 * 1024 * 1024) {
        fclose(f);
        return false;
    }

    // Read first 4 bytes to check for RIFF header
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) {
        fclose(f);
        return false;
    }

    if (memcmp(magic, "RIFF", 4) != 0) {
        // Not a WAV file — fall back to raw float32
        fseek(f, 0, SEEK_SET);
        std::vector<char> buf(fileSize);
        if (fread(buf.data(), 1, fileSize, f) != (size_t)fileSize) {
            fclose(f);
            return false;
        }
        fclose(f);
        size_t n = fileSize / sizeof(float);
        samples.resize(n);
        memcpy(samples.data(), buf.data(), n * sizeof(float));
        return !samples.empty();
    }

    // Parse WAV: skip file-size (4 bytes), then check "WAVE"
    char wavId[8]; // 4 bytes file-size + 4 bytes "WAVE"
    if (fread(wavId, 1, 8, f) != 8 || memcmp(wavId + 4, "WAVE", 4) != 0) {
        fclose(f);
        return false;
    }

    // Scan chunks to find "fmt " and "data"
    uint16_t audioFormat = 0;
    uint16_t numChannels = 0;
    uint32_t sampleRate = 0;
    uint16_t bitsPerSample = 0;
    bool fmtFound = false;

    const unsigned char* dataPtr = nullptr;
    uint32_t dataSize = 0;
    std::vector<unsigned char> fileData;

    // Read the rest of the file for chunk scanning
    long remaining = fileSize - 12; // already read 12 bytes (RIFF + size + WAVE)
    if (remaining <= 0) {
        fclose(f);
        return false;
    }
    fileData.resize(remaining);
    if (fread(fileData.data(), 1, remaining, f) != (size_t)remaining) {
        fclose(f);
        return false;
    }
    fclose(f);

    size_t pos = 0;
    while (pos + 8 <= (size_t)remaining) {
        const char* chunkId = (const char*)(fileData.data() + pos);
        uint32_t chunkSize;
        memcpy(&chunkSize, fileData.data() + pos + 4, 4);

        if (memcmp(chunkId, "fmt ", 4) == 0 && chunkSize >= 16 && pos + 8 + 16 <= (size_t)remaining) {
            const unsigned char* fmt = fileData.data() + pos + 8;
            memcpy(&audioFormat, fmt, 2);
            memcpy(&numChannels, fmt + 2, 2);
            memcpy(&sampleRate, fmt + 4, 4);
            // skip byte_rate (4) and block_align (2)
            memcpy(&bitsPerSample, fmt + 14, 2);
            fmtFound = true;
        } else if (memcmp(chunkId, "data", 4) == 0) {
            dataSize = chunkSize;
            if (pos + 8 + dataSize > (size_t)remaining) {
                dataSize = remaining - pos - 8;
            }
            dataPtr = fileData.data() + pos + 8;
            break; // found data chunk, stop scanning
        }

        // Advance to next chunk (chunks are word-aligned)
        pos += 8 + chunkSize;
        if (chunkSize % 2 != 0) pos++;
    }

    if (!fmtFound || !dataPtr || dataSize == 0) {
        LOGI("loadAudioFile: WAV missing fmt or data chunk");
        return false;
    }

    if (audioFormat != 1) {
        // Only PCM (format 1) is supported
        LOGI("loadAudioFile: unsupported WAV audio format %d (only PCM supported)", audioFormat);
        return false;
    }

    if (bitsPerSample != 16 && bitsPerSample != 32) {
        LOGI("loadAudioFile: unsupported bits_per_sample %d", bitsPerSample);
        return false;
    }

    // Convert PCM data to float32 mono samples
    size_t bytesPerSample = bitsPerSample / 8;
    size_t frameSize = bytesPerSample * numChannels;
    if (frameSize == 0) return false;
    size_t numFrames = dataSize / frameSize;

    std::vector<float> rawSamples(numFrames);

    if (bitsPerSample == 16) {
        for (size_t i = 0; i < numFrames; i++) {
            float sum = 0.0f;
            for (uint16_t ch = 0; ch < numChannels; ch++) {
                int16_t s;
                memcpy(&s, dataPtr + i * frameSize + ch * 2, 2);
                sum += s / 32768.0f;
            }
            rawSamples[i] = sum / numChannels;
        }
    } else if (bitsPerSample == 32) {
        for (size_t i = 0; i < numFrames; i++) {
            float sum = 0.0f;
            for (uint16_t ch = 0; ch < numChannels; ch++) {
                float s;
                memcpy(&s, dataPtr + i * frameSize + ch * 4, 4);
                sum += s;
            }
            rawSamples[i] = sum / numChannels;
        }
    }

    // Resample to 16kHz if needed
    const uint32_t targetRate = 16000;
    if (sampleRate == targetRate) {
        samples = std::move(rawSamples);
    } else if (sampleRate > 0) {
        // Linear interpolation resampling
        double ratio = (double)sampleRate / (double)targetRate;
        size_t outLen = (size_t)((double)numFrames / ratio);
        if (outLen == 0) return false;
        samples.resize(outLen);
        for (size_t i = 0; i < outLen; i++) {
            double srcIdx = i * ratio;
            size_t idx0 = (size_t)srcIdx;
            double frac = srcIdx - idx0;
            if (idx0 + 1 < numFrames) {
                samples[i] = (float)(rawSamples[idx0] * (1.0 - frac) + rawSamples[idx0 + 1] * frac);
            } else if (idx0 < numFrames) {
                samples[i] = rawSamples[idx0];
            } else {
                samples[i] = 0.0f;
            }
        }
        LOGI("loadAudioFile: resampled %uHz -> %uHz (%zu -> %zu samples)",
             sampleRate, targetRate, numFrames, outLen);
    } else {
        return false;
    }

    LOGI("loadAudioFile: loaded WAV %uch %uHz %ubit, %zu output samples",
         numChannels, sampleRate, bitsPerSample, samples.size());
    return !samples.empty();
}

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_getcapacitor_plugin_whispercpp_WhisperCpp_00024NativeBridge_initContext(
    JNIEnv* env, jclass, jstring jModelPath, jstring jParamsJson) {
    const char* path = env->GetStringUTFChars(jModelPath, nullptr);
    if (!path) return env->NewStringUTF("{}");

    // Parse the JSON params string
    std::string json;
    if (jParamsJson) {
        const char* jsonStr = env->GetStringUTFChars(jParamsJson, nullptr);
        if (jsonStr) {
            json = jsonStr;
            env->ReleaseStringUTFChars(jParamsJson, jsonStr);
        }
    }

    cap_whisper_context_params params = {};
    params.model_path = path;

    // Boolean fields (default false unless noted)
    params.use_gpu          = jsonGetBool(json, "use_gpu", false);
    params.use_progress_callback = jsonGetBool(json, "use_progress_callback", false);
    params.translate        = jsonGetBool(json, "translate", false);
    params.no_context       = jsonGetBool(json, "no_context", false);
    params.no_timestamps    = jsonGetBool(json, "no_timestamps", false);
    params.single_segment   = jsonGetBool(json, "single_segment", false);
    params.split_on_word    = jsonGetBool(json, "split_on_word", false);
    params.speed_up         = jsonGetBool(json, "speed_up", false);
    params.tdrz_enable      = jsonGetBool(json, "tdrz_enable", false);
    params.token_timestamps = jsonGetBool(json, "token_timestamps", false);

    // Integer fields with defaults matching iOS bridge
    params.n_threads        = jsonGetInt(json, "n_threads", 1);
    params.n_max_text_ctx   = jsonGetInt(json, "n_max_text_ctx", 16384);
    params.offset_ms        = jsonGetInt(json, "offset_ms", 0);
    params.duration_ms      = jsonGetInt(json, "duration_ms", 0);
    params.max_len          = jsonGetInt(json, "max_len", 0);
    params.max_tokens       = jsonGetInt(json, "max_tokens", 0);
    params.audio_ctx        = jsonGetInt(json, "audio_ctx", 0);
    params.beam_size        = jsonGetInt(json, "beam_size", 1);
    params.best_of          = jsonGetInt(json, "best_of", 1);
    params.max_initial_ts   = jsonGetInt(json, "max_initial_ts", 1);

    // Float fields with defaults matching iOS bridge
    params.temperature      = jsonGetFloat(json, "temperature", 0.0f);
    params.temperature_inc  = jsonGetFloat(json, "temperature_inc", 0.2f);
    params.entropy_thold    = jsonGetFloat(json, "entropy_thold", 2.4f);
    params.logprob_thold    = jsonGetFloat(json, "logprob_thold", -1.0f);
    params.no_speech_thold  = jsonGetFloat(json, "no_speech_thold", 0.6f);
    params.thold_pt         = jsonGetFloat(json, "thold_pt", 0.01f);
    params.thold_ptsum      = jsonGetFloat(json, "thold_ptsum", 0.01f);

    // Language: use provided value or nullptr (triggers detect_language)
    // These std::strings must stay alive until cap_whisper_init returns.
    std::string langStr = jsonGetString(json, "language");
    params.language = langStr.empty() ? nullptr : langStr.c_str();

    // detect_language: default true if no language specified, else use JSON value
    params.detect_language = params.language
        ? jsonGetBool(json, "detect_language", false)
        : jsonGetBool(json, "detect_language", true);

    // initial_prompt
    std::string promptStr = jsonGetString(json, "initial_prompt");
    params.initial_prompt = promptStr.empty() ? nullptr : promptStr.c_str();

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
    if (s_contexts.find(contextId) == s_contexts.end()) return env->NewStringUTF("{}");
    cap_whisper_context* ctx = s_contexts[contextId];

    // Parse params JSON
    std::string json;
    if (jParamsJson) {
        const char* jsonStr = env->GetStringUTFChars(jParamsJson, nullptr);
        if (jsonStr) {
            json = jsonStr;
            env->ReleaseStringUTFChars(jParamsJson, jsonStr);
        }
    }
    const char* dataStr = env->GetStringUTFChars(jAudioData, nullptr);
    if (!dataStr) return env->NewStringUTF("{}");
    std::vector<float> samples;
    if (isAudioFile == JNI_TRUE) {
        std::string filePath(dataStr);
        env->ReleaseStringUTFChars(jAudioData, dataStr);
        if (!loadAudioFile(filePath.c_str(), samples)) {
            return env->NewStringUTF("{}");
        }
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

    // Override defaults with caller-supplied JSON params
    fp->n_threads        = jsonGetInt(json, "n_threads", 1);
    fp->n_max_text_ctx   = jsonGetInt(json, "n_max_text_ctx", 16384);
    fp->offset_ms        = jsonGetInt(json, "offset_ms", 0);
    fp->duration_ms      = jsonGetInt(json, "duration_ms", 0);
    fp->translate        = jsonGetBool(json, "translate", false);
    fp->no_context       = jsonGetBool(json, "no_context", false);
    fp->no_timestamps    = jsonGetBool(json, "no_timestamps", false);
    fp->single_segment   = jsonGetBool(json, "single_segment", false);

    // language & detect_language – keep strings alive until cap_whisper_full returns
    std::string langStr = jsonGetString(json, "language");
    fp->language = langStr.empty() ? nullptr : langStr.c_str();
    fp->detect_language = fp->language
        ? jsonGetBool(json, "detect_language", false)
        : jsonGetBool(json, "detect_language", true);

    fp->split_on_word    = jsonGetBool(json, "split_on_word", false);
    fp->max_len          = jsonGetInt(json, "max_len", 0);
    fp->max_tokens       = jsonGetInt(json, "max_tokens", 0);
    fp->speed_up         = jsonGetBool(json, "speed_up", false);
    fp->audio_ctx        = jsonGetInt(json, "audio_ctx", 0);

    // initial_prompt – keep string alive until cap_whisper_full returns
    std::string promptStr = jsonGetString(json, "initial_prompt");
    fp->initial_prompt = promptStr.empty() ? nullptr : promptStr.c_str();

    fp->temperature      = jsonGetFloat(json, "temperature", 0.0f);
    fp->temperature_inc  = jsonGetFloat(json, "temperature_inc", 0.2f);
    fp->entropy_thold    = jsonGetFloat(json, "entropy_thold", 2.4f);
    fp->logprob_thold    = jsonGetFloat(json, "logprob_thold", -1.0f);
    fp->no_speech_thold  = jsonGetFloat(json, "no_speech_thold", 0.6f);
    fp->max_initial_ts   = jsonGetFloat(json, "max_initial_ts", 1.0f);
    fp->beam_size        = jsonGetInt(json, "beam_size", 1);
    fp->best_of          = jsonGetInt(json, "best_of", 1);
    fp->tdrz_enable      = jsonGetBool(json, "tdrz_enable", false);
    fp->token_timestamps = jsonGetBool(json, "token_timestamps", false);
    fp->thold_pt         = jsonGetFloat(json, "thold_pt", 0.01f);
    fp->thold_ptsum      = jsonGetFloat(json, "thold_ptsum", 0.01f);

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
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    if (nprocs <= 0) nprocs = 1;

    long memoryMb = 0;
    struct sysinfo si;
    if (sysinfo(&si) == 0) {
        memoryMb = (long)(((unsigned long long)si.totalram * si.mem_unit) / (1024ULL * 1024ULL));
    }

    std::ostringstream out;
    out << "{\"platform\":\"android\""
        << ",\"gpu_available\":false"
        << ",\"max_threads\":" << nprocs
        << ",\"memory_available_mb\":" << memoryMb << "}";
    return env->NewStringUTF(out.str().c_str());
}

} // extern "C"
