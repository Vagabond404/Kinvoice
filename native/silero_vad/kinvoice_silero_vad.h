#ifndef KINVOICE_SILERO_VAD_H
#define KINVOICE_SILERO_VAD_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define KINVOICE_EXPORT __declspec(dllexport)
#else
  #define KINVOICE_EXPORT __attribute__((visibility("default")))
#endif

/**
 * Opaque handle representing a Silero VAD session and recurrent state context.
 */
typedef struct SileroVadContext SileroVadContext;

/**
 * Configuration parameters for Silero VAD.
 */
typedef struct {
  int32_t sample_rate;       // Default: 16000
  int32_t frame_size;        // Default: 512 samples (32ms at 16kHz)
  float threshold;           // Onset threshold, e.g. 0.5f
  float min_silence_dur_ms;  // Offset silence window, e.g. 800ms
} SileroVadConfig;

/**
 * Creates and initializes a Silero VAD session from an ONNX model file.
 * Returns NULL if model initialization fails.
 */
KINVOICE_EXPORT SileroVadContext* silero_vad_create(
    const char* model_path,
    int32_t sample_rate
);

/**
 * Processes a 512-sample 16kHz Float32 audio frame (normalized -1.0 to 1.0).
 * Updates internal recurrent state tensors and returns voice probability [0.0, 1.0].
 */
KINVOICE_EXPORT float silero_vad_process_frame(
    SileroVadContext* ctx,
    const float* audio_frame,
    int32_t frame_size
);

/**
 * Resets the recurrent hidden state tensor to zeros (e.g., when a speech segment finishes).
 */
KINVOICE_EXPORT void silero_vad_reset(SileroVadContext* ctx);

/**
 * Releases native session resources, tensor memory, and ONNX environment handles.
 */
KINVOICE_EXPORT void silero_vad_destroy(SileroVadContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // KINVOICE_SILERO_VAD_H
