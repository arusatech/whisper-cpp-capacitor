// WASM bindings for cap-whisper via Emscripten embind.
// Exposes init, free, transcribe, model info, and system info to JavaScript.

#include "cap-whisper.h"
#include <emscripten.h>
#include <emscripten/bind.h>
#include <cstring>
#include <map>
#include <string>
#include <sstream>
#include <thread>
#include <vector>

static std::map<int, cap_whisper_context*> s_contexts;
static int s_nextId = 1;

// Progress state for JS polling
static int s_progress = 0;
static void progress_cb(int progress, void* /*user_data*/) {
    s_progress = progress;
}

static std::string escapeJson(const char* s) {
    if (!s) return "\"\"";
    std::string o = "\"";
    for (; *s; s++) {
        if (*s == '"') o += "\\\"";
        else if (*s == '\\') o += "\\\\";
        else if (*s == '\n') o += "\\n";
        else if (*s == '\r') o += "\\r";
        else if (*s == '\t') o += "\\t";
        else o += *s;
    }
    o += "\"";
    return o;
}

// Returns JSON string: {"contextId":N,"model":{...},"gpu":false,"reasonNoGPU":"..."}
static std::string wasmInit(const std::string& modelPath, bool useGpu, int nThreads) {
    cap_whisper_context_params params = {};
    params.model_path = modelPath.c_str();
    params.use_gpu = false; // WASM has no GPU
    params.n_threads = nThreads > 0 ? nThreads : 1;
    params.n_max_text_ctx = 16384;
    params.detect_language = true;
    params.temperature = 0.0f;
    params.temperature_inc = 0.2f;
    params.entropy_thold = 2.4f;
    params.logprob_thold = -1.0f;
    params.no_speech_thold = 0.6f;
    params.beam_size = 1;
    params.best_of = 1;
    params.thold_pt = 0.01f;
    params.thold_ptsum = 0.01f;
    params.max_initial_ts = 1.0f;

    bool outUseGpu = false;
    char reasonBuf[256] = {0};
    cap_whisper_context* ctx = cap_whisper_init(
        modelPath.c_str(), &params, &outUseGpu, reasonBuf, sizeof(reasonBuf));
    if (!ctx) return "{}";

    int id = s_nextId++;
    s_contexts[id] = ctx;

    cap_whisper_model_info info = {};
    if (cap_whisper_get_model_info(ctx, &info) != 0) {
        cap_whisper_free(ctx);
        s_contexts.erase(id);
        return "{}";
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
        << ",\"gpu\":false"
        << ",\"reasonNoGPU\":\"WASM does not support GPU\"}";
    cap_whisper_model_info_free(&info);
    return out.str();
}

static bool wasmFree(int contextId) {
    auto it = s_contexts.find(contextId);
    if (it == s_contexts.end()) return false;
    cap_whisper_free(it->second);
    s_contexts.erase(it);
    return true;
}

static void wasmFreeAll() {
    for (auto& p : s_contexts) cap_whisper_free(p.second);
    s_contexts.clear();
}

// Transcribe float32 PCM samples. Returns JSON result string.
static std::string wasmTranscribe(
    int contextId,
    uintptr_t samplesPtr, int nSamples,
    int nThreads, bool translate, const std::string& language,
    bool detectLanguage, bool tokenTimestamps, bool tdrzEnable,
    int beamSize, int bestOf, float temperature,
    const std::string& initialPrompt, bool useProgressCallback
) {
    auto it = s_contexts.find(contextId);
    if (it == s_contexts.end()) return "{}";

    const float* samples = reinterpret_cast<const float*>(samplesPtr);

    cap_whisper_full_params* fp = cap_whisper_full_params_default();
    if (!fp) return "{}";

    fp->n_threads = nThreads > 0 ? nThreads : 1;
    fp->translate = translate;
    fp->language = language.empty() ? nullptr : language.c_str();
    fp->detect_language = detectLanguage;
    fp->token_timestamps = tokenTimestamps;
    fp->tdrz_enable = tdrzEnable;
    fp->beam_size = beamSize > 0 ? beamSize : 1;
    fp->best_of = bestOf > 0 ? bestOf : 1;
    fp->temperature = temperature;
    fp->initial_prompt = initialPrompt.empty() ? nullptr : initialPrompt.c_str();

    if (useProgressCallback) {
        s_progress = 0;
        fp->progress_callback = progress_cb;
        fp->progress_callback_user_data = nullptr;
    }

    cap_whisper_result result = {};
    int ret = cap_whisper_full(it->second, samples, nSamples, fp, &result);
    cap_whisper_full_params_free(fp);

    if (ret != 0) return "{}";

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
    out << "],\"words\":[";
    for (int i = 0; i < result.n_words; i++) {
        if (i) out << ",";
        out << "{\"word\":" << escapeJson(result.words[i].word)
            << ",\"start\":" << result.words[i].start_ms
            << ",\"end\":" << result.words[i].end_ms
            << ",\"confidence\":" << result.words[i].confidence << "}";
    }
    out << "]}";
    cap_whisper_result_free(&result);
    return out.str();
}

static std::string wasmGetModelInfo(int contextId) {
    auto it = s_contexts.find(contextId);
    if (it == s_contexts.end()) return "{}";
    cap_whisper_model_info info = {};
    if (cap_whisper_get_model_info(it->second, &info) != 0) return "{}";
    std::ostringstream out;
    out << "{\"type\":" << escapeJson(info.type)
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
        << ",\"ftype\":" << info.ftype << "}";
    cap_whisper_model_info_free(&info);
    return out.str();
}

static int wasmGetProgress() { return s_progress; }

// Allocate WASM memory for float samples — JS calls this, writes data, then calls transcribe
static uintptr_t wasmMalloc(int bytes) {
    void* p = malloc(bytes);
    return reinterpret_cast<uintptr_t>(p);
}

static void wasmFreePtr(uintptr_t ptr) {
    free(reinterpret_cast<void*>(ptr));
}

EMSCRIPTEN_BINDINGS(cap_whisper_wasm) {
    emscripten::function("init", &wasmInit);
    emscripten::function("free_context", &wasmFree);
    emscripten::function("free_all", &wasmFreeAll);
    emscripten::function("transcribe", &wasmTranscribe);
    emscripten::function("get_model_info", &wasmGetModelInfo);
    emscripten::function("get_progress", &wasmGetProgress);
    emscripten::function("wasm_malloc", &wasmMalloc);
    emscripten::function("wasm_free", &wasmFreePtr);
}
