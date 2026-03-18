#include "cap-whisper.h"
#include "whisper.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static char* strdup_safe(const char* s) {
  if (!s) return nullptr;
  size_t n = std::strlen(s) + 1;
  char* p = (char*)malloc(n);
  if (p) std::memcpy(p, s, n);
  return p;
}

static void cap_whisper_context_params_to_whisper(const cap_whisper_context_params* cap, struct whisper_context_params* out) {
  out->use_gpu = cap->use_gpu;
  out->flash_attn = false;
  out->gpu_device = -1;
  out->dtw_token_timestamps = false;
  out->dtw_n_top = 1;
  out->dtw_aheads_preset = WHISPER_AHEADS_NONE;
  out->dtw_aheads.n_heads = 0;
  out->dtw_aheads.heads = nullptr;
  out->dtw_mem_size = 0;
}

static void cap_whisper_full_params_to_whisper(const cap_whisper_full_params* cap, struct whisper_full_params* w) {
  w->n_threads = cap->n_threads > 0 ? cap->n_threads : 1;
  w->n_max_text_ctx = cap->n_max_text_ctx;
  w->offset_ms = cap->offset_ms;
  w->duration_ms = cap->duration_ms;
  w->translate = cap->translate;
  w->no_context = cap->no_context;
  w->no_timestamps = cap->no_timestamps;
  w->single_segment = cap->single_segment;
  w->print_special = false;
  w->print_progress = false;
  w->print_realtime = false;
  w->print_timestamps = false;
  w->token_timestamps = cap->token_timestamps;
  w->thold_pt = cap->thold_pt;
  w->thold_ptsum = cap->thold_ptsum;
  w->max_len = cap->max_len;
  w->split_on_word = cap->split_on_word;
  w->max_tokens = cap->max_tokens;
  w->audio_ctx = cap->audio_ctx;
  w->tdrz_enable = cap->tdrz_enable;
  w->initial_prompt = cap->initial_prompt;
  w->prompt_tokens = cap->prompt_tokens;
  w->prompt_n_tokens = cap->prompt_n_tokens;
  w->language = cap->language;
  w->detect_language = cap->detect_language;
  w->temperature = cap->temperature;
  w->max_initial_ts = cap->max_initial_ts;
  w->temperature_inc = cap->temperature_inc;
  w->entropy_thold = cap->entropy_thold;
  w->logprob_thold = cap->logprob_thold;
  w->no_speech_thold = cap->no_speech_thold;
  w->greedy.best_of = cap->best_of;
  w->beam_search.beam_size = cap->beam_size;
  w->new_segment_callback = nullptr;
  w->new_segment_callback_user_data = nullptr;
  w->progress_callback = nullptr;
  w->progress_callback_user_data = nullptr;
  w->encoder_begin_callback = nullptr;
  w->encoder_begin_callback_user_data = nullptr;
  w->abort_callback = nullptr;
  w->abort_callback_user_data = nullptr;
  w->logits_filter_callback = nullptr;
  w->logits_filter_callback_user_data = nullptr;
  w->grammar_rules = nullptr;
  w->n_grammar_rules = 0;
  w->i_start_rule = 0;
  w->grammar_penalty = 0;
  w->vad = false;
  w->vad_model_path = nullptr;
}

struct cap_whisper_context {
  struct whisper_context* ctx;
};

extern "C" {

cap_whisper_context* cap_whisper_init(const char* path_model, const cap_whisper_context_params* params, bool* out_use_gpu, char* reason_no_gpu, size_t reason_no_gpu_size) {
  if (!path_model || !params) return nullptr;
  struct whisper_context_params cparams = whisper_context_default_params();
  cap_whisper_context_params_to_whisper(params, &cparams);
  cparams.use_gpu = params->use_gpu;
  struct whisper_context* ctx = whisper_init_from_file_with_params(path_model, cparams);
  if (!ctx) return nullptr;
  if (out_use_gpu) *out_use_gpu = cparams.use_gpu;
  if (reason_no_gpu && reason_no_gpu_size > 0) {
    const char* msg = "GPU not used";
    size_t len = strlen(msg);
    if (len >= reason_no_gpu_size) len = reason_no_gpu_size - 1;
    memcpy(reason_no_gpu, msg, len);
    reason_no_gpu[len] = '\0';
  }
  cap_whisper_context* cap = (cap_whisper_context*)malloc(sizeof(cap_whisper_context));
  if (!cap) {
    whisper_free(ctx);
    return nullptr;
  }
  cap->ctx = ctx;
  return cap;
}

void cap_whisper_free(cap_whisper_context* ctx) {
  if (!ctx) return;
  whisper_free(ctx->ctx);
  free(ctx);
}

static const char* model_type_str(int t) {
  switch (t) {
    case 0: return "tiny";
    case 1: return "base";
    case 2: return "small";
    case 3: return "medium";
    case 4: return "large";
    default: return "unknown";
  }
}

int cap_whisper_get_model_info(cap_whisper_context* ctx, cap_whisper_model_info* out) {
  if (!ctx || !out) return -1;
  out->type = strdup_safe(whisper_model_type_readable(ctx->ctx));
  if (!out->type) out->type = strdup_safe(model_type_str(whisper_model_type(ctx->ctx)));
  out->is_multilingual = whisper_is_multilingual(ctx->ctx);
  out->vocab_size = whisper_n_vocab(ctx->ctx);
  out->n_audio_ctx = whisper_model_n_audio_ctx(ctx->ctx);
  out->n_audio_state = whisper_model_n_audio_state(ctx->ctx);
  out->n_audio_head = whisper_model_n_audio_head(ctx->ctx);
  out->n_audio_layer = whisper_model_n_audio_layer(ctx->ctx);
  out->n_text_ctx = whisper_n_text_ctx(ctx->ctx);
  out->n_text_state = whisper_model_n_text_state(ctx->ctx);
  out->n_text_head = whisper_model_n_text_head(ctx->ctx);
  out->n_text_layer = whisper_model_n_text_layer(ctx->ctx);
  out->n_mels = whisper_model_n_mels(ctx->ctx);
  out->ftype = whisper_model_ftype(ctx->ctx);
  return 0;
}

void cap_whisper_model_info_free(cap_whisper_model_info* info) {
  if (!info) return;
  free(info->type);
  info->type = nullptr;
}

int cap_whisper_full(cap_whisper_context* ctx, const float* samples, int n_samples, const cap_whisper_full_params* params, cap_whisper_result* out_result) {
  if (!ctx || !samples || !out_result) return -1;
  memset(out_result, 0, sizeof(cap_whisper_result));
  enum whisper_sampling_strategy strategy = (params && params->beam_size > 1) ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY;
  struct whisper_full_params wparams = whisper_full_default_params(strategy);
  if (params) cap_whisper_full_params_to_whisper(params, &wparams);
  int ret = whisper_full(ctx->ctx, wparams, samples, n_samples);
  if (ret != 0) return ret;
  int n_seg = whisper_full_n_segments(ctx->ctx);
  int lang_id = whisper_full_lang_id(ctx->ctx);
  const char* lang_str = whisper_lang_str(lang_id);
  out_result->language = strdup_safe(lang_str ? lang_str : "en");
  out_result->language_prob = 0.0f;
  out_result->n_segments = n_seg;
  out_result->n_words = 0;
  out_result->duration_ms = n_samples * 1000 / 16000;
  struct whisper_timings* timings = whisper_get_timings(ctx->ctx);
  out_result->processing_time_ms = timings ? (int64_t)(timings->encode_ms + timings->decode_ms) : 0;
  std::string full_text;
  if (n_seg > 0) {
    out_result->segments = (cap_whisper_segment*)calloc((size_t)n_seg, sizeof(cap_whisper_segment));
    if (!out_result->segments) return -2;
    for (int i = 0; i < n_seg; i++) {
      cap_whisper_segment* seg = &out_result->segments[i];
      int64_t t0 = whisper_full_get_segment_t0(ctx->ctx, i);
      int64_t t1 = whisper_full_get_segment_t1(ctx->ctx, i);
      const char* text = whisper_full_get_segment_text(ctx->ctx, i);
      seg->start_ms = t0 * 10;
      seg->end_ms = t1 * 10;
      seg->text = strdup_safe(text ? text : "");
      seg->no_speech_prob = whisper_full_get_segment_no_speech_prob(ctx->ctx, i);
      seg->speaker_turn_next = whisper_full_get_segment_speaker_turn_next(ctx->ctx, i);
      seg->speaker_id = 0;
      if (text) full_text += text;
    }
  }
  out_result->text = strdup_safe(full_text.c_str());
  if (params && params->token_timestamps && n_seg > 0) {
    std::vector<cap_whisper_word> words;
    for (int i = 0; i < n_seg; i++) {
      int n_tok = whisper_full_n_tokens(ctx->ctx, i);
      for (int j = 0; j < n_tok; j++) {
        whisper_token_data td = whisper_full_get_token_data(ctx->ctx, i, j);
        const char* tok_text = whisper_full_get_token_text(ctx->ctx, i, j);
        if (tok_text && tok_text[0]) {
          cap_whisper_word w;
          w.word = strdup_safe(tok_text);
          w.start_ms = td.t0 * 10;
          w.end_ms = td.t1 * 10;
          w.confidence = td.p;
          words.push_back(w);
        }
      }
    }
    out_result->n_words = (int)words.size();
    if (out_result->n_words > 0) {
      out_result->words = (cap_whisper_word*)malloc((size_t)out_result->n_words * sizeof(cap_whisper_word));
      if (out_result->words)
        memcpy(out_result->words, words.data(), (size_t)out_result->n_words * sizeof(cap_whisper_word));
    }
  }
  return 0;
}

void cap_whisper_result_free(cap_whisper_result* result) {
  if (!result) return;
  free(result->text);
  result->text = nullptr;
  free(result->language);
  result->language = nullptr;
  if (result->segments) {
    for (int i = 0; i < result->n_segments; i++) {
      free(result->segments[i].text);
      result->segments[i].text = nullptr;
    }
    free(result->segments);
    result->segments = nullptr;
  }
  result->n_segments = 0;
  if (result->words) {
    for (int i = 0; i < result->n_words; i++) {
      free(result->words[i].word);
      result->words[i].word = nullptr;
    }
    free(result->words);
    result->words = nullptr;
  }
  result->n_words = 0;
}

cap_whisper_full_params* cap_whisper_full_params_default(void) {
  cap_whisper_full_params* p = (cap_whisper_full_params*)malloc(sizeof(cap_whisper_full_params));
  if (!p) return nullptr;
  memset(p, 0, sizeof(*p));
  p->n_threads = 1;
  p->n_max_text_ctx = 16384;
  p->translate = false;
  p->no_context = false;
  p->no_timestamps = false;
  p->single_segment = false;
  p->detect_language = true;
  p->temperature = 0.0f;
  p->temperature_inc = 0.2f;
  p->entropy_thold = 2.4f;
  p->logprob_thold = -1.0f;
  p->no_speech_thold = 0.6f;
  p->beam_size = 1;
  p->best_of = 1;
  p->token_timestamps = false;
  p->thold_pt = 0.01f;
  p->thold_ptsum = 0.01f;
  p->max_initial_ts = 1.0f;
  return p;
}

void cap_whisper_full_params_free(cap_whisper_full_params* p) {
  free(p);
}

} // extern "C"
