#ifndef CAP_WHISPER_H
#define CAP_WHISPER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cap_whisper_context cap_whisper_context;
typedef struct cap_whisper_context_params cap_whisper_context_params;
typedef struct cap_whisper_full_params cap_whisper_full_params;
typedef struct cap_whisper_segment cap_whisper_segment;
typedef struct cap_whisper_word cap_whisper_word;
typedef struct cap_whisper_result cap_whisper_result;
typedef struct cap_whisper_model_info cap_whisper_model_info;

struct cap_whisper_context_params {
  const char* model_path;
  bool use_gpu;
  bool use_progress_callback;
  int n_threads;
  int n_max_text_ctx;
  int offset_ms;
  int duration_ms;
  bool translate;
  bool no_context;
  bool no_timestamps;
  bool single_segment;
  const char* language;
  bool detect_language;
  bool split_on_word;
  int max_len;
  int max_tokens;
  bool speed_up;
  int audio_ctx;
  const char* initial_prompt;
  const int32_t* prompt_tokens;
  int prompt_n_tokens;
  float temperature;
  float temperature_inc;
  float entropy_thold;
  float logprob_thold;
  float no_speech_thold;
  int beam_size;
  int best_of;
  bool tdrz_enable;
  bool token_timestamps;
  float thold_pt;
  float thold_ptsum;
  int max_initial_ts;
};

struct cap_whisper_segment {
  int64_t start_ms;
  int64_t end_ms;
  char* text;
  float no_speech_prob;
  bool speaker_turn_next;
  int speaker_id;
};

struct cap_whisper_word {
  char* word;
  int64_t start_ms;
  int64_t end_ms;
  float confidence;
};

struct cap_whisper_result {
  char* text;
  cap_whisper_segment* segments;
  int n_segments;
  cap_whisper_word* words;
  int n_words;
  char* language;
  float language_prob;
  int64_t duration_ms;
  int64_t processing_time_ms;
};

struct cap_whisper_model_info {
  char* type;
  bool is_multilingual;
  int vocab_size;
  int n_audio_ctx;
  int n_audio_state;
  int n_audio_head;
  int n_audio_layer;
  int n_text_ctx;
  int n_text_state;
  int n_text_head;
  int n_text_layer;
  int n_mels;
  int ftype;
};

cap_whisper_context* cap_whisper_init(const char* path_model, const cap_whisper_context_params* params, bool* out_use_gpu, char* reason_no_gpu, size_t reason_no_gpu_size);
void cap_whisper_free(cap_whisper_context* ctx);

int cap_whisper_get_model_info(cap_whisper_context* ctx, cap_whisper_model_info* out);
void cap_whisper_model_info_free(cap_whisper_model_info* info);

int cap_whisper_full(cap_whisper_context* ctx, const float* samples, int n_samples, const cap_whisper_full_params* params, cap_whisper_result* out_result);
void cap_whisper_result_free(cap_whisper_result* result);

struct cap_whisper_full_params {
  int n_threads;
  int n_max_text_ctx;
  int offset_ms;
  int duration_ms;
  bool translate;
  bool no_context;
  bool no_timestamps;
  bool single_segment;
  const char* language;
  bool detect_language;
  bool split_on_word;
  int max_len;
  int max_tokens;
  bool speed_up;
  int audio_ctx;
  const char* initial_prompt;
  const int32_t* prompt_tokens;
  int prompt_n_tokens;
  float temperature;
  float temperature_inc;
  float entropy_thold;
  float logprob_thold;
  float no_speech_thold;
  float max_initial_ts;
  int beam_size;
  int best_of;
  bool tdrz_enable;
  bool token_timestamps;
  float thold_pt;
  float thold_ptsum;
};

cap_whisper_full_params* cap_whisper_full_params_default(void);
void cap_whisper_full_params_free(cap_whisper_full_params* p);

#ifdef __cplusplus
}
#endif

#endif
