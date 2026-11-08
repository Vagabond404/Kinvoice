#include "kinvoice_silero_vad.h"

#include <vector>
#include <cmath>
#include <cstring>
#include <memory>
#include <iostream>

#if __has_include(<onnxruntime_cxx_api.h>)
  #include <onnxruntime_cxx_api.h>
  #define HAS_ONNX_RUNTIME 1
#else
  #define HAS_ONNX_RUNTIME 0
#endif

// Silero VAD v5 constants
constexpr int32_t SILERO_DEFAULT_SR = 16000;
constexpr int32_t SILERO_FRAME_SIZE = 512;
constexpr int64_t STATE_DIMS[3] = {2, 1, 128};
constexpr size_t STATE_SIZE = 2 * 1 * 128; // 256 floats

struct SileroVadContext {
  int32_t sample_rate{SILERO_DEFAULT_SR};
  int32_t frame_size{SILERO_FRAME_SIZE};
  std::vector<float> state; // Recurrent state buffer [2, 1, 128]
  int64_t sr_value{SILERO_DEFAULT_SR};

#if HAS_ONNX_RUNTIME
  std::unique_ptr<Ort::Env> env;
  std::unique_ptr<Ort::Session> session;
  std::unique_ptr<Ort::MemoryInfo> memory_info;
#endif

  SileroVadContext(int32_t sr) : sample_rate(sr), frame_size(SILERO_FRAME_SIZE) {
    state.resize(STATE_SIZE, 0.0f);
    sr_value = static_cast<int64_t>(sample_rate);
  }
};

extern "C" {

KINVOICE_EXPORT SileroVadContext* silero_vad_create(
    const char* model_path,
    int32_t sample_rate
) {
  if (sample_rate != 8000 && sample_rate != 16000) {
    sample_rate = SILERO_DEFAULT_SR;
  }

  auto ctx = std::make_unique<SileroVadContext>(sample_rate);

#if HAS_ONNX_RUNTIME
  try {
    ctx->env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "KinvoiceSileroVad");
    Ort::SessionOptions session_options;
    session_options.SetIntraOpNumThreads(1);
    session_options.SetInterOpNumThreads(1);
    session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

#if defined(_WIN32)
    // Convert UTF-8 path to wide string on Windows
    int wlen = MultiByteToWideChar(CP_UTF8, 0, model_path, -1, nullptr, 0);
    std::wstring wpath(wlen, 0);
    MultiByteToWideChar(CP_UTF8, 0, model_path, -1, &wpath[0], wlen);
    ctx->session = std::make_unique<Ort::Session>(*ctx->env, wpath.c_str(), session_options);
#else
    ctx->session = std::make_unique<Ort::Session>(*ctx->env, model_path, session_options);
#endif

    ctx->memory_info = std::make_unique<Ort::MemoryInfo>(
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)
    );
  } catch (const std::exception& e) {
    std::cerr << "Silero VAD Initialization Error: " << e.what() << std::endl;
    return nullptr;
  }
#endif

  return ctx.release();
}

KINVOICE_EXPORT float silero_vad_process_frame(
    SileroVadContext* ctx,
    const float* audio_frame,
    int32_t frame_size
) {
  if (!ctx || !audio_frame || frame_size != ctx->frame_size) {
    return 0.0f;
  }

#if HAS_ONNX_RUNTIME
  if (!ctx->session) {
    return 0.0f;
  }

  try {
    // 1. Prepare input audio tensor [1, 512]
    int64_t input_shape[2] = {1, static_cast<int64_t>(frame_size)};
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        *ctx->memory_info,
        const_cast<float*>(audio_frame),
        frame_size,
        input_shape,
        2
    );

    // 2. Prepare state tensor [2, 1, 128]
    int64_t state_shape[3] = {STATE_DIMS[0], STATE_DIMS[1], STATE_DIMS[2]};
    Ort::Value state_tensor = Ort::Value::CreateTensor<float>(
        *ctx->memory_info,
        ctx->state.data(),
        ctx->state.size(),
        state_shape,
        3
    );

    // 3. Prepare sample rate tensor [1]
    int64_t sr_shape[1] = {1};
    Ort::Value sr_tensor = Ort::Value::CreateTensor<int64_t>(
        *ctx->memory_info,
        &ctx->sr_value,
        1,
        sr_shape,
        1
    );

    const char* input_names[] = {"input", "state", "sr"};
    const char* output_names[] = {"output", "state"};

    std::vector<Ort::Value> input_tensors;
    input_tensors.push_back(std::move(input_tensor));
    input_tensors.push_back(std::move(state_tensor));
    input_tensors.push_back(std::move(sr_tensor));

    // 4. Execute inference
    auto output_tensors = ctx->session->Run(
        Ort::RunOptions{nullptr},
        input_names,
        input_tensors.data(),
        input_tensors.size(),
        output_names,
        2
    );

    // 5. Read probability output
    float* output_data = output_tensors[0].GetTensorMutableData<float>();
    float prob = output_data[0];

    // 6. Update internal recurrent state from model output
    float* new_state_data = output_tensors[1].GetTensorMutableData<float>();
    std::memcpy(ctx->state.data(), new_state_data, STATE_SIZE * sizeof(float));

    // Clamp probability [0.0, 1.0]
    if (prob < 0.0f) prob = 0.0f;
    if (prob > 1.0f) prob = 1.0f;
    return prob;
  } catch (const std::exception& e) {
    std::cerr << "Silero VAD Inference Error: " << e.what() << std::endl;
    return 0.0f;
  }
#else
  // Fallback heuristic energy-based estimation when ONNX native library is absent
  double sum_squares = 0.0;
  for (int32_t i = 0; i < frame_size; ++i) {
    float s = audio_frame[i];
    sum_squares += s * s;
  }
  float rms = std::sqrt(sum_squares / frame_size);
  float prob = std::min(1.0f, rms * 4.0f);
  return prob;
#endif
}

KINVOICE_EXPORT void silero_vad_reset(SileroVadContext* ctx) {
  if (ctx) {
    std::fill(ctx->state.begin(), ctx->state.end(), 0.0f);
  }
}

KINVOICE_EXPORT void silero_vad_destroy(SileroVadContext* ctx) {
  if (ctx) {
    delete ctx;
  }
}

} // extern "C"
