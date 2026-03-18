#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef struct cap_whisper_context cap_whisper_context;
typedef struct cap_whisper_context_params cap_whisper_context_params;
typedef struct cap_whisper_full_params cap_whisper_full_params;
typedef struct cap_whisper_result cap_whisper_result;
typedef struct cap_whisper_model_info cap_whisper_model_info;

static void* s_whisperLib = nil;

static bool loadWhisperLib(void) {
    if (s_whisperLib) return true;
    NSString* path = [[NSBundle mainBundle] pathForResource:@"WhisperCpp" ofType:@"framework"];
    if (!path) path = [[NSBundle mainBundle] pathForResource:@"WhisperCpp" ofType:@"framework" inDirectory:@"Frameworks"];
    if (!path) return false;
    s_whisperLib = dlopen(path.UTF8String, RTLD_NOW);
    return s_whisperLib != nil;
}

#define PTR(name) (dlsym(s_whisperLib, #name))

static NSMutableDictionary<NSNumber*, NSValue*>* s_contextMap = nil;
static int s_nextContextId = 1;

static void ensureContextMap(void) {
    if (!s_contextMap) s_contextMap = [NSMutableDictionary new];
}

static cap_whisper_context_params paramsFromDict(NSDictionary* d, NSString* modelPath) {
    cap_whisper_context_params p = {};
    p.model_path = modelPath.UTF8String;
    p.use_gpu = [d[@"use_gpu"] boolValue];
    p.use_progress_callback = [d[@"use_progress_callback"] boolValue];
    p.n_threads = [d[@"n_threads"] intValue] ?: 1;
    p.n_max_text_ctx = [d[@"n_max_text_ctx"] intValue] ?: 16384;
    p.offset_ms = [d[@"offset_ms"] intValue];
    p.duration_ms = [d[@"duration_ms"] intValue];
    p.translate = [d[@"translate"] boolValue];
    p.no_context = [d[@"no_context"] boolValue];
    p.no_timestamps = [d[@"no_timestamps"] boolValue];
    p.single_segment = [d[@"single_segment"] boolValue];
    NSString* lang = d[@"language"];
    p.language = lang.length ? lang.UTF8String : nil;
    p.detect_language = [d[@"detect_language"] boolValue];
    p.split_on_word = [d[@"split_on_word"] boolValue];
    p.max_len = [d[@"max_len"] intValue];
    p.max_tokens = [d[@"max_tokens"] intValue];
    p.speed_up = [d[@"speed_up"] boolValue];
    p.audio_ctx = [d[@"audio_ctx"] intValue];
    NSString* prompt = d[@"initial_prompt"];
    p.initial_prompt = prompt.length ? prompt.UTF8String : nil;
    p.temperature = [d[@"temperature"] floatValue] ?: 0.0f;
    p.temperature_inc = [d[@"temperature_inc"] floatValue] ?: 0.2f;
    p.entropy_thold = [d[@"entropy_thold"] floatValue] ?: 2.4f;
    p.logprob_thold = [d[@"logprob_thold"] floatValue] ?: -1.0f;
    p.no_speech_thold = [d[@"no_speech_thold"] floatValue] ?: 0.6f;
    p.beam_size = [d[@"beam_size"] intValue] ?: 1;
    p.best_of = [d[@"best_of"] intValue] ?: 1;
    p.tdrz_enable = [d[@"tdrz_enable"] boolValue];
    p.token_timestamps = [d[@"token_timestamps"] boolValue];
    p.thold_pt = [d[@"thold_pt"] floatValue] ?: 0.01f;
    p.thold_ptsum = [d[@"thold_ptsum"] floatValue] ?: 0.01f;
    p.max_initial_ts = [d[@"max_initial_ts"] floatValue] ?: 1.0f;
    return p;
}

static void fillFullParams(NSDictionary* d, cap_whisper_full_params* p) {
    if (!p) return;
    p->n_threads = [d[@"n_threads"] intValue] ?: 1;
    p->n_max_text_ctx = [d[@"n_max_text_ctx"] intValue] ?: 16384;
    p->offset_ms = [d[@"offset_ms"] intValue];
    p->duration_ms = [d[@"duration_ms"] intValue];
    p->translate = [d[@"translate"] boolValue];
    p->no_context = [d[@"no_context"] boolValue];
    p->no_timestamps = [d[@"no_timestamps"] boolValue];
    p->single_segment = [d[@"single_segment"] boolValue];
    NSString* lang = d[@"language"];
    p->language = lang.length ? lang.UTF8String : nil;
    p->detect_language = [d[@"detect_language"] boolValue];
    p->split_on_word = [d[@"split_on_word"] boolValue];
    p->max_len = [d[@"max_len"] intValue];
    p->max_tokens = [d[@"max_tokens"] intValue];
    p->speed_up = [d[@"speed_up"] boolValue];
    p->audio_ctx = [d[@"audio_ctx"] intValue];
    NSString* prompt = d[@"initial_prompt"];
    p->initial_prompt = prompt.length ? prompt.UTF8String : nil;
    p->temperature = [d[@"temperature"] floatValue] ?: 0.0f;
    p->temperature_inc = [d[@"temperature_inc"] floatValue] ?: 0.2f;
    p->entropy_thold = [d[@"entropy_thold"] floatValue] ?: 2.4f;
    p->logprob_thold = [d[@"logprob_thold"] floatValue] ?: -1.0f;
    p->no_speech_thold = [d[@"no_speech_thold"] floatValue] ?: 0.6f;
    p->max_initial_ts = [d[@"max_initial_ts"] floatValue] ?: 1.0f;
    p->beam_size = [d[@"beam_size"] intValue] ?: 1;
    p->best_of = [d[@"best_of"] intValue] ?: 1;
    p->tdrz_enable = [d[@"tdrz_enable"] boolValue];
    p->token_timestamps = [d[@"token_timestamps"] boolValue];
    p->thold_pt = [d[@"thold_pt"] floatValue] ?: 0.01f;
    p->thold_ptsum = [d[@"thold_ptsum"] floatValue] ?: 0.01f;
}

@interface WhisperCppBridge : NSObject
+ (NSDictionary* _Nullable)initContextWithModelPath:(NSString*)path params:(NSDictionary*)params error:(NSError* _Nullable*)error;
+ (BOOL)releaseContext:(NSInteger)contextId error:(NSError* _Nullable*)error;
+ (void)releaseAllContexts;
+ (NSDictionary* _Nullable)transcribeWithContextId:(NSInteger)contextId samples:(const float*)samples count:(int)nSamples params:(NSDictionary*)params error:(NSError* _Nullable*)error;
+ (NSDictionary* _Nullable)getModelInfoForContextId:(NSInteger)contextId error:(NSError* _Nullable*)error;
+ (NSDictionary*)getSystemInfo;
@end

@implementation WhisperCppBridge

+ (NSDictionary* _Nullable)initContextWithModelPath:(NSString*)path params:(NSDictionary*)params error:(NSError* _Nullable*)error {
    if (!loadWhisperLib()) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"WhisperCpp.framework not found. Run build-native.sh and embed the framework."}];
        return nil;
    }
    typedef cap_whisper_context* (*init_fn_t)(const char*, const cap_whisper_context_params*, bool*, char*, size_t);
    init_fn_t init_fn = (init_fn_t)PTR(cap_whisper_init);
    if (!init_fn) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Native symbols not found"}];
        return nil;
    }
    ensureContextMap();
    cap_whisper_context_params p = paramsFromDict(params ?: @{}, path);
    bool useGpu = false;
    char reasonBuf[256] = {0};
    cap_whisper_context* ctx = init_fn(path.UTF8String, &p, &useGpu, reasonBuf, sizeof(reasonBuf));
    if (!ctx) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load model"}];
        return nil;
    }
    int cid = s_nextContextId++;
    s_contextMap[@(cid)] = [NSValue valueWithPointer:(void*)ctx];

    typedef int (*get_info_fn_t)(cap_whisper_context*, cap_whisper_model_info*);
    typedef void (*model_info_free_fn_t)(cap_whisper_model_info*);
    typedef void (*free_fn_t)(cap_whisper_context*);
    get_info_fn_t get_info_fn = (get_info_fn_t)PTR(cap_whisper_get_model_info);
    model_info_free_fn_t model_info_free_fn = (model_info_free_fn_t)PTR(cap_whisper_model_info_free);
    free_fn_t free_fn = (free_fn_t)PTR(cap_whisper_free);
    cap_whisper_model_info info = {};
    if (!get_info_fn || get_info_fn(ctx, &info) != 0) {
        if (free_fn) free_fn(ctx);
        [s_contextMap removeObjectForKey:@(cid)];
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get model info"}];
        return nil;
    }
    NSDictionary* modelDict = @{
        @"type": info.type ? [NSString stringWithUTF8String:info.type] : @"unknown",
        @"is_multilingual": @(info.is_multilingual),
        @"vocab_size": @(info.vocab_size),
        @"n_audio_ctx": @(info.n_audio_ctx),
        @"n_audio_state": @(info.n_audio_state),
        @"n_audio_head": @(info.n_audio_head),
        @"n_audio_layer": @(info.n_audio_layer),
        @"n_text_ctx": @(info.n_text_ctx),
        @"n_text_state": @(info.n_text_state),
        @"n_text_head": @(info.n_text_head),
        @"n_text_layer": @(info.n_text_layer),
        @"n_mels": @(info.n_mels),
        @"ftype": @(info.ftype)
    };
    if (model_info_free_fn) model_info_free_fn(&info);

    return @{
        @"contextId": @(cid),
        @"model": modelDict,
        @"gpu": @(useGpu),
        @"reasonNoGPU": @(reasonBuf)
    };
}

+ (BOOL)releaseContext:(NSInteger)contextId error:(NSError* _Nullable*)error {
    if (!loadWhisperLib()) return NO;
    typedef void (*free_fn_t)(cap_whisper_context*);
    free_fn_t free_fn = (free_fn_t)PTR(cap_whisper_free);
    if (!free_fn) return NO;
    ensureContextMap();
    NSValue* v = s_contextMap[@(contextId)];
    if (!v) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Context not found"}];
        return NO;
    }
    cap_whisper_context* ctx = (cap_whisper_context*)v.pointerValue;
    free_fn(ctx);
    [s_contextMap removeObjectForKey:@(contextId)];
    return YES;
}

+ (void)releaseAllContexts {
    if (!loadWhisperLib()) return;
    typedef void (*free_fn_t)(cap_whisper_context*);
    free_fn_t free_fn = (free_fn_t)PTR(cap_whisper_free);
    ensureContextMap();
    for (NSNumber* key in s_contextMap) {
        cap_whisper_context* ctx = (cap_whisper_context*)[s_contextMap[key] pointerValue];
        if (free_fn) free_fn(ctx);
    }
    [s_contextMap removeAllObjects];
}

+ (NSDictionary* _Nullable)transcribeWithContextId:(NSInteger)contextId samples:(const float*)samples count:(int)nSamples params:(NSDictionary*)params error:(NSError* _Nullable*)error {
    if (!loadWhisperLib()) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"WhisperCpp.framework not found"}];
        return nil;
    }
    typedef cap_whisper_full_params* (*params_default_fn_t)(void);
    typedef void (*params_free_fn_t)(cap_whisper_full_params*);
    typedef int (*full_fn_t)(cap_whisper_context*, const float*, int, const cap_whisper_full_params*, cap_whisper_result*);
    typedef void (*result_free_fn_t)(cap_whisper_result*);
    params_default_fn_t params_default_fn = (params_default_fn_t)PTR(cap_whisper_full_params_default);
    params_free_fn_t params_free_fn = (params_free_fn_t)PTR(cap_whisper_full_params_free);
    full_fn_t full_fn = (full_fn_t)PTR(cap_whisper_full);
    result_free_fn_t result_free_fn = (result_free_fn_t)PTR(cap_whisper_result_free);
    if (!params_default_fn || !full_fn) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Native symbols not found"}];
        return nil;
    }
    ensureContextMap();
    NSValue* v = s_contextMap[@(contextId)];
    if (!v) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Context not found"}];
        return nil;
    }
    cap_whisper_context* ctx = (cap_whisper_context*)v.pointerValue;
    cap_whisper_full_params* fp = params_default_fn();
    fillFullParams(params ?: @{}, fp);
    cap_whisper_result result = {};
    int ret = full_fn(ctx, samples, nSamples, fp, &result);
    if (params_free_fn) params_free_fn(fp);
    if (ret != 0) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:ret userInfo:@{NSLocalizedDescriptionKey: @"Transcription failed"}];
        return nil;
    }
    NSMutableArray* segments = [NSMutableArray array];
    for (int i = 0; i < result.n_segments; i++) {
        [segments addObject:@{
            @"start": @(result.segments[i].start_ms),
            @"end": @(result.segments[i].end_ms),
            @"text": result.segments[i].text ? [NSString stringWithUTF8String:result.segments[i].text] : @"",
            @"no_speech_prob": @(result.segments[i].no_speech_prob),
            @"speaker_id": @(result.segments[i].speaker_id)
        }];
    }
    NSMutableArray* words = [NSMutableArray array];
    for (int i = 0; i < result.n_words; i++) {
        [words addObject:@{
            @"word": result.words[i].word ? [NSString stringWithUTF8String:result.words[i].word] : @"",
            @"start": @(result.words[i].start_ms),
            @"end": @(result.words[i].end_ms),
            @"confidence": @(result.words[i].confidence)
        }];
    }
    NSDictionary* out = @{
        @"text": result.text ? [NSString stringWithUTF8String:result.text] : @"",
        @"segments": segments,
        @"words": words,
        @"language": result.language ? [NSString stringWithUTF8String:result.language] : @"en",
        @"language_prob": @(result.language_prob),
        @"duration_ms": @(result.duration_ms),
        @"processing_time_ms": @(result.processing_time_ms)
    };
    if (result_free_fn) result_free_fn(&result);
    return out;
}

+ (NSDictionary* _Nullable)getModelInfoForContextId:(NSInteger)contextId error:(NSError* _Nullable*)error {
    if (!loadWhisperLib()) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"WhisperCpp.framework not found"}];
        return nil;
    }
    typedef int (*get_info_fn_t)(cap_whisper_context*, cap_whisper_model_info*);
    typedef void (*model_info_free_fn_t)(cap_whisper_model_info*);
    get_info_fn_t get_info_fn = (get_info_fn_t)PTR(cap_whisper_get_model_info);
    model_info_free_fn_t model_info_free_fn = (model_info_free_fn_t)PTR(cap_whisper_model_info_free);
    if (!get_info_fn) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Native symbols not found"}];
        return nil;
    }
    ensureContextMap();
    NSValue* v = s_contextMap[@(contextId)];
    if (!v) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Context not found"}];
        return nil;
    }
    cap_whisper_context* ctx = (cap_whisper_context*)v.pointerValue;
    cap_whisper_model_info info = {};
    if (get_info_fn(ctx, &info) != 0) {
        if (error) *error = [NSError errorWithDomain:@"WhisperCpp" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get model info"}];
        return nil;
    }
    NSDictionary* d = @{
        @"type": info.type ? [NSString stringWithUTF8String:info.type] : @"unknown",
        @"is_multilingual": @(info.is_multilingual),
        @"vocab_size": @(info.vocab_size),
        @"n_audio_ctx": @(info.n_audio_ctx),
        @"n_audio_state": @(info.n_audio_state),
        @"n_audio_head": @(info.n_audio_head),
        @"n_audio_layer": @(info.n_audio_layer),
        @"n_text_ctx": @(info.n_text_ctx),
        @"n_text_state": @(info.n_text_state),
        @"n_text_head": @(info.n_text_head),
        @"n_text_layer": @(info.n_text_layer),
        @"n_mels": @(info.n_mels),
        @"ftype": @(info.ftype)
    };
    if (model_info_free_fn) model_info_free_fn(&info);
    return d;
}

+ (NSDictionary*)getSystemInfo {
    return @{
        @"platform": @"ios",
        @"gpu_available": @YES,
        @"max_threads": @(NSProcessInfo.processInfo.processorCount),
        @"memory_available_mb": @(0)
    };
}

@end
