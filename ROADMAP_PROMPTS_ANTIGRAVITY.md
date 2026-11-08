# Kinvoice — Sequential Antigravity 2.0 Implementation Roadmap
*Step-by-step master prompt sequence for building Kinvoice with Flutter & Antigravity 2.0 (Gemini 3.8 Flash High)*

---

## Overview & Execution Protocol

This roadmap defines the exact sequential prompts to provide to **Antigravity 2.0** (`Gemini 3.8 Flash High`). Each prompt is self-contained, specifies precise file targets, enforces clean architecture, and forbids placeholders or mock logic.

### Rules for Executing Each Prompt
- Feed one prompt at a time.
- Verify `flutter analyze` and `flutter test` pass with 0 errors before proceeding to the next prompt.
- Never let the agent refactor working earlier modules unless explicitly asked.
- All code must adhere strictly to `RULES_AGENT_KINVOICE.md`.

---

## Sequential Prompts

### Prompt 1: Project Scaffolding, Stitch Theme & Navigation Shell

```markdown
Role: Senior Flutter Systems Architect & UI Engineer.
Context: Building "Kinvoice", an ambient on-device voice recorder and AI second brain app.
Task: Initialize the clean architecture directory structure, design system tokens derived from Google Stitch, and the root navigation shell.

Directory Structure to generate:
lib/
  ├── core/
  │    ├── theme/ (app_colors.dart, app_typography.dart, app_theme.dart)
  │    ├── constants/ (route_constants.dart, storage_keys.dart)
  │    └── utils/ (result.dart, failure.dart)
  ├── features/
  │    ├── home/presentation/screens/ (home_screen.dart)
  │    ├── search/presentation/screens/ (search_screen.dart)
  │    └── settings/presentation/screens/ (settings_screen.dart)
  └── main.dart

Technical Requirements:
1. Define Theme Tokens in `core/theme/`:
   - Primary: Deep Indigo `#1E1B4B`
   - Accent: Electric Violet `#6366F1`
   - Background Light: `#F8FAFC`, Dark: `#0B0F19`
   - Surface Light: `#FFFFFF`, Dark: `#111827`
   - Surface Container Light: `#F1F5F9`, Dark: `#1F2937`
   - Text Primary: `#0F172A` (Light) / `#F9FAFB` (Dark)
   - Text Secondary: `#64748B` (Light) / `#9CA3AF` (Dark)
   - Font Family: Inter with variable weights (400, 500, 600, 700).
2. Set up Material 3 ThemeData supporting automatic Light & Dark switching.
3. Build a bottom navigation bar with 3 tabs:
   - Tab 1: "Timeline" (Icon: Icons.mic_rounded) -> HomeScreen placeholder
   - Tab 2: "Ask Memory" (Icon: Icons.auto_awesome_rounded) -> SearchScreen placeholder
   - Tab 3: "Settings" (Icon: Icons.tune_rounded) -> SettingsScreen placeholder
4. Provide unit tests in `test/core/theme_test.dart` verifying all color tokens and theme brightness modes.

Deliverables:
- Full, non-truncated implementations of all specified files.
- Zero placeholder comments like `// TODO`.
```

---

### Prompt 2: Home Screen Feed, Quick Action Bar & Filter System

```markdown
Role: Senior Flutter UI Specialist.
Context: Implementing Feature 1 for Kinvoice (Timeline / Home Screen).
Task: Build the Home Screen UI matching the Google Stitch aesthetic, including the Hero Quick-Record Card, Filter Chips, and the chronologically grouped recording feed.

Requirements:
1. Create `lib/features/home/presentation/widgets/`:
   - `hero_quick_record_card.dart`: Interactive top card with animated gradient border, greeting ("Capture your mind"), and a pulsing record action button.
   - `time_filter_selector.dart`: Horizontal scrollable pill filter row: "All", "Today", "This Week", "Favorites", "Meetings", "Ideas".
   - `recording_feed_item.dart`: Card displaying audio recording metadata:
     * Title (auto-generated or user edited)
     * Recording timestamp & duration formatted as mm:ss
     * Speaker badge count (e.g., "2 Speakers")
     * Key tags (e.g., "#Work", "#Decision")
     * Mini static waveform preview (Canvas CustomPainter)
     * Bookmark star icon and playback trigger
2. Create `lib/features/home/domain/models/recording_summary.dart`:
   - Fields: id, title, createdAt, durationSeconds, transcriptSnippet, speakers, tags, isFavorite, audioFilePath.
3. Implement `HomeScreen` in `lib/features/home/presentation/screens/home_screen.dart` using a CustomScrollView with Slivers for smooth 120Hz scrolling.
4. Add state management using a lightweight `ChangeNotifier` or `StateNotifier` (`HomeViewModel`) with mock data providing 5 realistic recordings.

Deliverables:
- Complete Dart files ready to compile with zero missing dependencies.
- Widget tests for `RecordingFeedItem` and `HeroQuickRecordCard`.
```

---

### Prompt 3: Audio Recording Engine & Active Recording Screen

```markdown
Role: Senior Flutter Audio Engineer & C++/FFI Specialist.
Context: Implementing audio recording and live visualization for Kinvoice.
Task: Build the low-latency audio capture service on a dedicated Dart Isolate with live RMS amplitude streaming and the Active Recording full-screen modal.

Requirements:
1. Audio Pipeline (`lib/core/audio/`):
   - `audio_recorder_service.dart`: High-level service handling start/pause/resume/stop.
   - Configure audio format: 16kHz, 16-bit Mono PCM (standard input for Silero VAD, Moonshine & Whisper).
   - Audio buffer processing must run inside a background `Isolate` (`audio_capture_isolate.dart`) to ensure zero main-thread UI jank.
   - Emit live audio chunk stream and compute normalized RMS amplitude (0.0 to 1.0) at 30 FPS.
2. Active Recording Modal (`lib/features/recording/presentation/screens/recording_screen.dart`):
   - Fullscreen dark mode interface.
   - Center visualizer: dynamic sine-wave or bar visualizer (`live_waveform_painter.dart`) reacting smoothly to RMS amplitude via `AnimationController`.
   - Recording timer formatted as `HH:MM:SS`.
   - Controls: Cancel button (trash icon), Pause/Resume toggle, Finish/Save button (check icon).
   - Speaker diarization preview: dynamically show active detected voice indicator.
3. Save output to temporary WAV/PCM file in the app's document directory upon completion.

Deliverables:
- Full audio engine and presentation layer code.
- Mock recorder test to verify amplitude calculation algorithms without requiring physical microphone hardware during unit tests.
```

---

### Prompt 4: Local Storage, SQLite FTS5 Engine & Audio Player

```markdown
Role: Senior Flutter Database & Systems Engineer.
Context: Kinvoice persistence and audio playback architecture.
Task: Implement local SQLite persistence with Full-Text Search (FTS5) using `drift` or `sqflite`, along with the Recording Detail screen and scrubbable audio player.

Requirements:
1. Database Layer (`lib/core/database/`):
   - Create tables: `Recordings`, `Segments` (id, recording_id, start_ms, end_ms, speaker_id, text), and `RecordingsFTS` (FTS5 virtual table indexing title, transcript, and tags).
   - Migration-ready schema with transactional inserts for bulk audio segments.
   - Full-text search repository query matching query terms across transcript segments with snippet generation.
2. Audio Player Service (`lib/core/audio/audio_player_service.dart`):
   - Seamless playback of local audio files with position, duration, and buffering streams.
   - Playback speed control: 1.0x, 1.25x, 1.5x, 2.0x.
   - Seeking with millisecond precision.
3. Recording Detail Screen (`lib/features/player/presentation/screens/player_screen.dart`):
   - Header with editable title, date, duration, and export actions (.SRT, .TXT, .WAV).
   - Scrubbable waveform track showing elapsed time and drag-to-seek support.
   - Interactive segmented transcript list: clicking any segment seeks audio to `start_ms` and highlights the currently active segment during playback.
   - Speaker re-naming dialog (change "Speaker 1" to "Ange" across all segments).

Deliverables:
- Complete database schemas, queries, and repository layer.
- Player UI and playback engine with zero placeholder code.
- Unit tests validating FTS5 queries and search snippet extraction.
```

---

### Prompt 5: Ambient Background Listening & Silero VAD Integration

```markdown
Role: Senior Mobile Platform Architect (Android/iOS) & C++ FFI Developer.
Context: Ambient hands-free voice detection for Kinvoice.
Task: Implement continuous background audio monitoring with Silero VAD v5 running on a Dart background worker isolate, integrated with native platform foreground services.

Requirements:
1. Silero VAD Integration (`lib/core/ml/vad/`):
   - `silero_vad_engine.dart`: Load `silero_vad.onnx` (v5, 2MB) using `onnxruntime` FFI.
   - Process 512-sample frames (32ms at 16kHz).
   - Return voice probability score (0.0 to 1.0).
   - State machine: detect speech onset (prob > 0.5 for 3 consecutive frames) and speech offset (prob < 0.35 for 800ms) to automatically create segmented recordings without user intervention.
2. Native Background Handling:
   - Android: Setup `ForegroundService` with notification channel "Ambient Voice Ear", displaying "Kinvoice is listening in low-power ambient mode".
   - iOS: Configure `AVAudioSessionCategoryPlayAndRecord` with options `allowBluetooth` and `mixWithOthers`, declaring background audio in Info.plist.
3. Battery Optimization Protocol:
   - Sleep cycle when silence exceeds 30 seconds.
   - CPU throttling and buffer caching.
4. Settings Toggle:
   - Enable/disable Ambient Mode with a quick master switch.

Deliverables:
- C++/Dart FFI bindings for ONNX Runtime Silero VAD.
- Complete background service registration and lifecycles.
- Unit tests simulating raw PCM audio streams with known voice/silence patterns.
```

---

### Prompt 6: On-Device Speech-to-Text & Speaker Diarization

```markdown
Role: Senior On-Device AI/ML Specialist.
Context: 100% private transcription and multi-speaker separation for Kinvoice.
Task: Implement on-device Moonshine ASR and ECAPA-TDNN speaker diarization on a dedicated background worker isolate.

Requirements:
1. Speech-to-Text Pipeline (`lib/core/ml/asr/`):
   - `asr_engine.dart`: Interface supporting both Moonshine Base (4-bit ONNX) and Whisper.cpp Small (GGUF).
   - Multi-language support: English (primary) and optional Khmer (Meta MMS Conformer).
   - Word-level timestamp generation (start_time, end_time, confidence, word).
   - Output structured segments with punctuation capitalization.
2. Speaker Diarization Pipeline (`lib/core/ml/diarization/`):
   - `diarization_engine.dart`: ECAPA-TDNN model producing 192-dimensional speaker embeddings from 1-second audio windows.
   - Cosine similarity clustering algorithm: automatically cluster speaker embeddings into Speaker A, Speaker B, Speaker C without external server calls.
   - Align speaker labels with ASR transcript segments.
3. Worker Isolate Coordinator (`lib/core/ml/transcription_worker.dart`):
   - Receive raw audio file path, execute VAD -> Diarization -> ASR sequentially.
   - Emit progress events (0% to 100%) to the main thread.
   - Store generated segments in the SQLite database.

Deliverables:
- Complete ML orchestration pipeline running in background isolates.
- Pure Dart cosine similarity clustering implementation.
- Integration tests simulating the transcription pipeline with mock ONNX tensors.
```

---

### Prompt 7: "Ask Your Memory" Semantic Q&A & Local Model Hub

```markdown
Role: Senior AI Application Engineer.
Context: Final feature integration for Kinvoice.
Task: Build the "Ask Your Memory" natural language query screen, vector embeddings search, and the on-device Model Hub with BYOK (Bring Your Own Key) support.

Requirements:
1. Local Vector Search (`lib/core/ai/vector_search/`):
   - Embedding generator using `all-MiniLM-L6-v2` ONNX (22MB).
   - Vector store in SQLite using cosine distance matching against transcript chunks.
   - Hybrid retrieval: Combine SQLite FTS5 keyword results with semantic vector similarity scores.
2. Ask Memory Screen (`lib/features/search/presentation/screens/search_screen.dart`):
   - Conversational search bar: "What did I decide in yesterday's meeting about marketing?"
   - Generative answer summary card citing exact voice notes with clickable timestamp chips.
   - Relevant audio clips preview player embedded inside search results.
3. Model Hub & BYOK Settings (`lib/features/settings/presentation/screens/model_hub_screen.dart`):
   - Download Manager: Visual cards for on-device models (Silero VAD 2MB, Moonshine 38MB, Khmer MMS 42MB, Whisper Small 140MB). Progress bar, delete/download actions, storage breakdown.
   - BYOM/BYOK Custom API Configuration: Support optional custom endpoint (OpenAI compatible, Groq, Ollama, Gemini API) with secure encrypted storage via `flutter_secure_storage`.
   - Export All Data: 1-click JSON/ZIP backup of all local recordings and transcripts.

Deliverables:
- Complete vector search, UI presentation, and Model Hub code.
- Unit and widget tests for hybrid search retrieval.
```

---

## Post-Generation Verification Checklist
After executing the 7 prompts:
- [ ] Run `flutter analyze` — zero warnings and zero errors.
- [ ] Run `flutter test` — all unit and widget tests pass.
- [ ] Test on real Android/iOS device: record 30s audio, verify background isolate performance (<3% CPU on ambient mode).
- [ ] Verify FTS5 and semantic search return correct quotes with exact time offsets.
