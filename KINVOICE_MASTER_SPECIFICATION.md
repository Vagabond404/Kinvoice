# 🎙️ KINVOICE — Master Product & Technical Specification (v1.0)

**Project Name**: Kinvoice  
**Tagline**: *Never lose a word that matters. Ambient Voice Memory & Pro Audio Studio.*  
**Primary Target Platform**: Flutter (iOS & Android)  
**Primary Application Language**: English (100% English UI, Multilingual ASR)  
**Date of Document**: November 8, 2026  
**Lead & Owner**: Ange  

---

## 🧭 1. Executive Summary & Core Value Proposition

**Kinvoice** is a dual-engine ambient voice recorder and AI second brain designed for creators, students, professionals, and families worldwide.

It seamlessly unifies two distinct paradigms into a cohesive, battery-efficient mobile application:
1. **The Ambient Second Brain (Continuous Passive Capture)**: An ultra-low power background listener (consuming less than 0.5% battery) that continuously detects human speech, buffers conversations, identifies distinct speakers (e.g., Mom, Best Friend, Boss, Self), transcribes speech locally in real-time, and indexes it into an interactive semantic memory. Users can simply ask: *"What did Mom tell me about the weekend market?"* and instantly receive a precise factual answer with a playable 10-second audio proof snippet.
2. **The Pro Audio Studio (Manual Recording & Subtitles)**: A broadcast-quality manual recorder featuring real-time 120 FPS audio waveforms, AGC (Automatic Gain Control), live tagging markers, and 1-tap export of `.wav` audio, `.srt` subtitle files (with word-level timestamps for video editing in Premiere or CapCut), and clean transcripts.

---

## 🎨 2. Google Stitch MCP Server Integration

The UI design system and screen assets are centrally managed in Google Stitch. Any AI coding agent (including Antigravity 2.0) working on this codebase must reference the live Stitch project using the following MCP configuration:

```json
{
  "mcpServers": {
    "stitch": {
      "serverUrl": "https://stitch.googleapis.com/mcp",
      "headers": {
        "X-Goog-Api-Key": "YOUR_STITCH_API_KEY"
      }
    }
  }
}
```

### Visual Language & Design Tokens
* **Aesthetic**: Modern, luminous, human-centric, distraction-free.
* **Color Palette**:
  * Canvas Background: Pure White (`#FFFFFF`) and Warm Pale Slate (`#F9FAFB`).
  * Surface Cards: Clean white cards with soft subtle borders (`#E2E8F0`) and smooth drop shadows (`shadow-sm` / `0 2px 8px rgba(0,0,0,0.04)`).
  * Primary Accent: Modern Electric Indigo (`#4F46E5`) for buttons, active tabs, and primary actions.
  * Recording / Alert Accent: Soft Coral Red (`#EF4444`) for recording and pause triggers.
  * Active Presence: Soft Emerald Mint (`#10B981`) for the passive listening badge.
  * Geometry: Card border-radius `24px` (`rounded-2xl` / `rounded-3xl`).
  * Typography: Clean sans-serif (Inter or SF Pro Display) with high hierarchy and legibility.

---

## 📱 3. Detailed Screen Specifications

The application uses an intuitive 3-tab bottom navigation dock: `[Recordings]` (Home), `[Ask Memory]` (AI Search), and `[Settings]` (Model Hub & Preferences).

### Screen 1: Home & Recordings Dashboard
* **Header**: App title **Kinvoice**, discrete passive status badge (`● Ambient Memory: Active`), user avatar, and Settings shortcut.
* **Hero Action Card**:
  * A prominent, inviting top card titled *"Capture Your Mind"*.
  * A large, soft-gradient circular Record button with a microphone icon for instant 1-tap manual recording.
  * Fast launch latency: starts recording in under 80ms.
* **Filter Bar**: Horizontal scrolling pill chips: `[All Recordings]` `[Daily Conversations]` `[Interviews]` `[Favorites]`.
* **Recent Recordings & Conversations Feed**:
  * Grouped chronologically (Today, Yesterday, Earlier this week).
  * Card attributes: Title, speaker avatar chips (e.g., `[Mom 👩]` `[Karusak 🥋]` `[You 🧑]`), duration, date/time.
  * 1-line clean conversational summary.
  * Inline audio waveform preview with quick 1-tap play button.

### Screen 2: Active Recording Experience (Live Studio)
* **Trigger**: Opens immediately when tapping *"Start Recording"*.
* **Top Navigation Bar**: Dismiss/Minimize button, editable recording title (defaults to *"New Recording #..."*), audio format pill (`WAV HQ 24-bit 48kHz`).
* **Center Visual Stage**:
  * Prominent digital clock timer: `00:04:18.42`.
  * Real-time fluid 60 FPS audio waveform visualizer reactive to voice amplitude.
* **Live Transcription Panel**:
  * Chat-style transcript bubbles appearing dynamically word-by-word as people speak.
  * Speaker tag displayed atop each bubble (e.g., `[You]`, `[Mom]`, `[Speaker 1]`).
* **Docked Control Actions**:
  * Left: `[+ Add Tag / Marker]` (flags key timestamps for later review).
  * Center: Large Red Pause / Resume Button.
  * Right: Blue Checkmark `[Done & Save]` Button.

### Screen 3: Recording Detail & Transcript Player
* **Header**: Back arrow, recording title, and Share/Export icon.
* **Interactive Player Card**:
  * Full audio scrubbable waveform with playback progress (`04:12 / 35:10`).
  * Skip back -15s, Play/Pause, Skip forward +15s, playback speed selector (`1.0x`, `1.5x`, `2.0x`).
  * 1-Tap Export Actions: `[Export Audio (WAV/M4A)]` `[Export Subtitles (.SRT)]` `[Export Text (.TXT)]`.
* **Smart Summary Card**: Luminous callout card containing 3 concise bullet points summarizing core decisions, dates, and topics.
* **Complete Attributed Transcript**: Chronological list of dialogue segments with timestamps and speaker tags.
* **In-Context Q&A Bar**: Sticky input at the bottom: *"Ask a question about this recording..."*.

### Screen 4: Ask Your Memory (AI Semantic Search)
* **Header**: *"Ask Your Memory"*, subtext: *"Search across all your spoken conversations."*
* **Search Input**: Clean prompt bar (e.g., *"What did my mom say about the gallery tuk-tuk?"*).
* **Filter Chips**: `[All People]` `[Mom 👩]` `[Karusak 🥋]` `[Today]` `[This Week]`.
* **Direct Answer Card**:
  * Synthesized answer: *"Your mother agreed to reimburse you 5,800 KHR for the tuk-tuk ride back from The River Gallery."*
  * Context Citation: *"Conversation on Friday, Nov 6 at 09:45 PM • 12s excerpt"*.
  * Inline Waveform Player: 1-tap audio playback of the exact 10-second quote.
* **Recent Inquiries**: List of past questions and topics.

### Screen 5: Settings, Model Hub & Custom Integrations
* **Settings Hub**:
  * Profile card: Local Storage Edition, 100% On-Device, Data Storage usage (`1.2 GB used`).
  * AI Model Hub (manage local models).
  * Voice Profiles (manage trained speakers).
  * Audio Quality & Noise Reduction.
  * Custom APIs & Self-Hosted Servers.
  * Privacy, Storage & Export all data.
* **AI Model Hub**:
  * Smart Dispatcher Auto-Pilot toggle (adapts models dynamically based on battery and language).
  * Active model card: Moonshine Base (4-bit, 38 MB, ⚡ 5x Real-Time, 91% Acc).
  * Downloadable Language Packs: Meta MMS Khmer (42 MB, 85% Acc on Khmer 🇰🇭), Whisper.cpp Small Q4 (95 MB, 96% Acc, Word-level SRT).
  * Custom Model Loader: Import `.onnx`, `.tflite`, or `.gguf` files directly.
* **Voice Profiles Manager**:
  * List of calibrated speakers: Mom 👩, Karusak 🥋, Ange 🧑.
  * 5-second voice calibration prompt to add new people.
* **Custom APIs (BYOK)**:
  * Optional fields for Groq API key, Google Gemini Flash API key, and OpenAI key.
  * Local Server URL (e.g., `http://192.168.1.50:11434` for Ollama/vLLM) with latency test button.

---

## ⚙️ 4. Technical Architecture & AI Engine Pipeline

### Threading & Zero-Lag Architecture (Clean Separation)
* **UI Isolate (Main Thread)**: Dedicated exclusively to Flutter rendering at 60/120 FPS. Absolutely no audio encoding, model inference, or file I/O runs on this thread.
* **Audio Capture Thread**: 16 kHz Mono stream with RNNoise / WebRTC AGC pre-processing and circular ring buffering.
* **VAD Isolate**: Silero VAD v5 (C++ ONNX Runtime via `dart:ffi`). Consumes < 0.5% CPU. Detects speech in 30ms frames; sleeps during silence.
* **Speaker Diarization Isolate**: ECAPA-TDNN (Sherpa-ONNX, 8 MB). Extracts a 192-dimensional vector embedding per speaker segment. Language-agnostic.
* **ASR Engine**:
  * Real-Time Stream: Moonshine Base (4-bit quantized ONNX) + Meta MMS Khmer Conformer.
  * Studio / Subtitle Mode: Whisper.cpp (Base/Small Q4) with dynamic time warping for millisecond-exact word timestamps.
* **Local Memory Database**: SQLite FTS5 (Full-Text Search) + `all-MiniLM-L6-v2` (25 MB) for semantic embedding search.

---

## 🔒 5. Privacy, Policy & Permissions

* **100% Local-First by Default**: Audio recordings and transcripts never leave the device unless the user explicitly configures an external API key.
* **Permissions Management**:
  * Microphone (`RECORD_AUDIO`): Handled gracefully with clear in-app rationale.
  * Background Service (`FOREGROUND_SERVICE_MICROPHONE` on Android): Runs with a discreet silent notification (*"Kinvoice is listening for voice notes"*).
  * Storage: Private app container storage.
* **GDPR & Export Compliance**: 1-click export of all audio and database files in standard `.zip` format, and 1-click permanent wipe.
