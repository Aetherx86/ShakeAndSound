# ShakeAndSound

A high-performance native macOS workstation uniting physical multi-modal chassis seismometry, low-latency digital signal processing (DSP), real-time acoustic sound classification, bilingual speech transcription with voice biometric diarization, and generative audio intelligence.

Built entirely with native Apple frameworks including SwiftUI, AVFoundation, Accelerate (vDSP), SoundAnalysis, Speech, and NaturalLanguage.

---

## Architecture Overview

```
+---------------------------------------------------------------------------------------------------+
|                                       ShakeAndSound macOS App                                     |
+---------------------------------+---------------------------------+-------------------------------+
|       Physical Seismometry      |       Acoustic DSP Studio       |      Audio Intelligence       |
+---------------------------------+---------------------------------+-------------------------------+
| - Chassis Acoustic Micro-Tap    | - AVAudioEngine 48kHz Pipeline  | - SoundAnalysis Classifier    |
| - Hardware Keystroke Velocity   | - vDSP FFT & 16-Band Spectrum   | - Speech Transcription        |
| - Trackpad Continuous Hover     | - F0 Pitch Tracking & Centroid  | - Voice Biometric Diarization |
| - STA/LTA Triggering Algorithm  | - Cybernetic Glass Visualizers  | - Dual Gemini / Local Summaries|
+---------------------------------+---------------------------------+-------------------------------+
```

ShakeAndSound operates across two synchronized sensing domains:
1. **Physical Kinetic & Structural Sensing ("Shake Seismo"):** Evaluates structural vibrations, impacts, and physical tampering by fusing low-latency microphonic chassis acoustics with hardware keystroke dynamics, trackpad hover velocity, and window kinematics into a calibrated seismogram.
2. **Acoustic & Audio Intelligence ("Sound Studio"):** Captures multi-channel microphone input to perform real-time spectral analysis, noise/cough filtering, bilingual speech-to-text recognition, biometric speaker diarization, and LLM-assisted conversation summarization.

---

## Core Subsystems

### 1. Multi-Modal Physical Seismograph (`SeismographService`)
The seismometry engine monitors kinetic disturbances on the host machine without requiring dedicated external hardware sensors.
- **Sensor Fusion:** Synthesizes low-frequency acoustic vibrations (micro-impacts transmitted through the MacBook or Mac chassis) with hardware keystroke events, trackpad hover vectors, and window drag kinematics.
- **PGA Computation:** Calculates real-time Peak Ground Acceleration (PGA) in milligravity ($mg$).
- **STA/LTA Trigger Detection:** Implements the geophysics-standard Short-Term Average to Long-Term Average ($STA/LTA$) ratio algorithm. Rapid energy transients exceed the dynamic threshold, triggering seismic event markers and event logging.
- **Helicorder Canvas:** Renders a continuous, real-time seismogram canvas with adjustable sensitivity and persistent state retention across application tab transitions.

### 2. High-Performance Digital Signal Processing (`AudioWaveformEngine`)
Built on top of Apple's `AVAudioEngine` and the `Accelerate` framework for zero-latency audio analysis.
- **Buffer Stream Pipeline:** Direct tapping of hardware input nodes providing 1024-sample PCM buffers at native sample rates (44.1 kHz / 48 kHz).
- **Fast Fourier Transform (FFT):** Employs `vDSP` discrete Fourier transforms to partition incoming audio into 16 discrete logarithmic frequency bands.
- **Acoustic Feature Extraction:** Computes instantaneous and smoothed RMS power levels, fundamental pitch tracking ($F_0$), and spectral centroids for vocal timbre characterization.
- **Voice Activity Detection (VAD):** Automatically detects vocal thresholds to govern downstream speech recognizers and reduce unnecessary background processing.

### 3. Sound Classification & Artifact Suppression (`AudioClassifierService`)
- **SoundAnalysis Integration:** Utilizes Apple's machine learning audio classification stream analyzer (`SNAudioStreamAnalyzer`) to detect environmental sound classes in real time.
- **Acoustic Noise Suppression:** Detects and flags non-speech vocal and environmental artifacts, including coughing, throat clearing, sneezing, typing clicks, breathing noises, and ambient clatter.
- **Event Audit Log:** Maintains a timestamped history of identified audio categories with confidence ratings and filtering statuses.

### 4. Bilingual Transcription & Voice Biometric Diarization (`SpeechTranscriptionService`)
- **Zero-Delay Speech Recognition:** Streams raw PCM buffers directly into `SFSpeechRecognizer` without intermediate disk caching or file encoding delays.
- **Dual-Language Processing:** Optimized for continuous Korean and English speech recognition with automatic punctuation and sentence segmentation.
- **Voice Biometric Diarization:** Differentiates speakers by extracting fundamental vocal pitch ($F_0$ in Hz), spectral centroids, and acoustic harmonics, automatically mapping spoken segments to distinct speaker identities ("Speaker 1", "Speaker 2", etc.).
- **Dual Presentation Views:** Supports both structured conversational segment cards (showing timestamps, speaker tags, pitch frequencies, and language tags) and an inline editable plain-text transcript buffer.

### 5. Multi-Engine Summarization & Intelligence (`SummarizationService`)
- **Cloud LLM Acceleration:** Integrated with the Google Gemini API, supporting `gemini-flash-lite-latest` and `gemini-flash-latest` for low-latency, cost-effective transcript structuring.
- **On-Device Fallback:** Provides zero-network, private on-device text summarization powered by Apple's `NaturalLanguage` framework (`NLLanguageRecognizer`, lexical tagging).
- **Structured Output:** Automatically generates high-level meeting overviews, actionable key takeaways, prioritized next steps, and participant speaker attributions.
- **Security Lock:** Protects stored API credentials using masked presentation, security lock toggles, and clipboard tamper prevention.

---

## User Interface & Visualizer Modes

ShakeAndSound features a cybernetic dark-glass visual interface styled for high-density monitoring:
- **Jarvis Wave:** Flowing harmonic bezier waveform that modulates amplitude and frequency in response to voice dynamics.
- **Siri Hologram:** Multi-layered pulsing orbital geometry reflecting vocal intensity and pitch shift.
- **Cyber Spectrum:** High-contrast 16-band neon bar graph showing real-time frequency distribution from sub-bass to treble.
- **Seismo Helicorder:** Continuous sweep-line seismograph with color-coded alerts indicating background ambient noise versus physical impact thresholds.

---

## Directory Structure

```
ShakeAndSound/
├── ShakeAndSound.xcodeproj           # Xcode project configuration
└── ShakeAndSound/
    ├── MyApp.swift                   # Application entry point
    ├── ContentView.swift             # Main sidebar and shell interface
    ├── SeismoView.swift              # Seismograph and helicorder canvas
    ├── SeismographService.swift      # Multi-modal physical shake detection
    ├── SoundVisualizerView.swift     # Waveform and spectrum visualizer views
    ├── AudioWaveformEngine.swift     # Audio capture, vDSP FFT, pitch tracking
    ├── AudioClassifierService.swift  # SoundAnalysis classifier and noise filter
    ├── SpeechTranscriptionService.swift # SFSpeechRecognizer and diarization
    ├── SummarizationService.swift    # Gemini API and on-device summarization
    └── Assets.xcassets/              # App icons, visual assets, and color sets
```

---

## Technical Specifications & Requirements

- **Platform:** macOS 14.0 (Sonoma) or later
- **Hardware Architecture:** Apple Silicon (M1/M2/M3/M4) and Intel x86_64
- **Toolchain:** Xcode 15.0+ / Swift 5.9+
- **Framework Dependencies:**
  - `SwiftUI`
  - `AVFoundation`
  - `Accelerate` (vDSP)
  - `SoundAnalysis`
  - `Speech`
  - `NaturalLanguage`
  - `AppKit`
  - `Combine`

---

## Building and Running

### Prerequisites
1. Clone the repository:
   ```bash
   git clone https://github.com/Aetherx86/ShakeAndSound.git
   cd ShakeAndSound
   ```

2. Open the project in Xcode:
   ```bash
   open ShakeAndSound.xcodeproj
   ```

3. Build and run:
   - Select the `ShakeAndSound` target.
   - Choose your Mac as the destination.
   - Press `Cmd + R` to build and run the application.

### Command Line Build
To compile a release binary directly from the terminal:
```bash
xcodebuild -project ShakeAndSound.xcodeproj \
           -scheme ShakeAndSound \
           -configuration Release \
           clean build
```

---

## System Permissions

To enable real-time sensing, macOS requires standard user authorization for:
- **Microphone Access (`NSMicrophoneUsageDescription`):** Required for real-time acoustic signal processing, sound classification, and physical chassis micro-vibration analysis.
- **Speech Recognition (`NSSpeechRecognitionUsageDescription`):** Required for on-device and streaming speech-to-text transcription.

---

## Security and Privacy

- **On-Device First:** All digital signal processing, spectrum decomposition, sound classification, and speech transcription run strictly on the local machine using native macOS subsystems.
- **Optional Cloud AI:** Connection to Google Gemini API occurs exclusively when the user enters a valid API key and requests cloud-based summarization. All credentials are stored locally with protective masking.

---

## Author & License

Copyright (c) 2026 Jeong Hoon Kim. All rights reserved.

Licensed under the MIT License.
