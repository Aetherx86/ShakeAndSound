# ShakeAndSound

A high-performance native macOS workstation and DSP library uniting physical multi-modal chassis seismometry, 3-axis gravity-isolated motion kinematics, procedural polyphonic audio synthesis, RIFF/WAVE PCM encoding, beat/tempo synchronization, real-time acoustic sound classification, bilingual speech transcription with voice biometric diarization, and structured transcript summarization.

Built entirely with native Apple frameworks including SwiftUI, AVFoundation, Accelerate (vDSP), SoundAnalysis, Speech, and NaturalLanguage.

---

## Architecture Overview

```
+---------------------------------------------------------------------------------------------------+
|                                   ShakeAndSound v0.2.0 Platform                                   |
+---------------------------------+---------------------------------+-------------------------------+
|       Physical Seismometry      |       Acoustic DSP Studio       |      Audio Intelligence       |
+---------------------------------+---------------------------------+-------------------------------+
| - Chassis Acoustic Micro-Tap    | - AVAudioEngine 48kHz Pipeline  | - SoundAnalysis Classifier    |
| - Gravity Isolation (LP/HP IIR) | - vDSP FFT & 16-Band Spectrum   | - Speech Transcription        |
| - 3-Axis Jerk & Arias Intensity | - Parabolic F0 Pitch Tracking   | - Voice Biometric Diarization |
| - Shake Pattern Classification  | - Polyphonic Synth & WAV Codec  | - Tempo Sync & Haptic Curves  |
| - STA/LTA Triggering Algorithm  | - Cybernetic Glass Visualizers  | - Cloud & On-Device Summaries |
+---------------------------------+---------------------------------+-------------------------------+
```

ShakeAndSound operates across two synchronized sensing domains plus a headless DSP command-line verification harness:
1. **Physical Kinetic & Structural Sensing ("Shake Seismo"):** Evaluates structural vibrations, impacts, and physical tampering by fusing low-latency microphonic chassis acoustics with hardware keystroke dynamics, trackpad hover velocity, window kinematics, low-pass/high-pass gravity isolation, and shake pattern recognition into a calibrated seismogram.
2. **Acoustic & Audio Intelligence ("Sound Studio"):** Captures multi-channel microphone input or procedural synthesized waveforms to perform real-time spectral analysis, noise/cough filtering, bilingual speech-to-text recognition, biometric speaker diarization, tempo/haptic curve synthesis, and conversation summarization.

---

## What's New in v0.2.0

### 1. DSP Motion Kinematics & Shake Pattern Recognition (`MotionKinematicsEngine`)
- **Dual-Stage Gravity Isolation:** Separates static 3-axis orientation/tilt gravity (`isolatedGravityMg`) from linear dynamic acceleration (`linearAccelerationMg`) using a first-order RC low-pass filter paired with a DC-blocking high-pass filter.
- **Kinematic Derivatives & Geophysical Integrals:** Computes 3-axis jerk ($\text{mg/s}$), leaky-integrated velocity ($\text{mm/s}$), crest factor, zero-crossing rate (Hz), autocorrelation dominant oscillation frequency (Hz), and cumulative Arias Intensity ($I_A = \frac{\pi}{2 g_0} \int a(t)^2 dt$).
- **Gesture & Shake Pattern Classification (`ShakePatternKind`):** Classifies sliding kinematic windows into `idle`, `micro_tremor`, `single_tap_impact`, `double_tap_impulse`, `rhythmic_lateral_shake`, and `seismic_shear_wave`.
- **Hostile-Input Hardening:** Guards against `NaN`, `+/-Infinity`, extreme outliers ($\pm 50,000\text{ mg}$), and invalid time steps.

### 2. Procedural Polyphonic Audio Synthesis & RIFF/WAVE Codec (`ProceduralAudioSynthesizer`, `WAVCodec`)
- **Polyphonic Waveform Synthesis:** Generates phase-continuous multi-voice audio across `sine`, `triangle`, `sawtooth`, `square`, `white_noise`, and `seismic_fm` oscillators with linear chirp sweeps, ADSR envelopes, and soft-knee `tanh` limiting.
- **Seismic Sonification:** Converts seismic acceleration and STA/LTA traces directly into frequency-modulated polyphonic audio buffers (`sonifySeismicTrace` and `SeismographService.exportRecentSeismicSonificationWAV`).
- **Parabolic Autocorrelation Pitch Detection:** Enhances `vDSP` autocorrelation $F_0$ estimation with parabolic lag interpolation for sub-sample frequency precision across offline and streaming PCM buffers.
- **Standards-Compliant RIFF/WAVE Codec:** Encodes and decodes 16-bit Little-Endian Linear PCM (and decodes 32-bit IEEE Float) `.wav` containers with full chunk header validation.

### 3. Beat/Tempo Synchronization & Adaptive Haptic/Audio Curves (`TempoHapticCurveEngine`)
- **Onset Flux & BPM Estimator:** Extracts half-wave rectified energy flux, picks peaks via adaptive local thresholds with refractory debouncing, and clusters octave-folded inter-onset intervals to estimate tempo (`40..220 BPM`) and beat phase.
- **Transfer Curves & Dynamic Compression:** Evaluates strictly bounded `[0.0, 1.0]` response curves (`linear`, `exponential`, `logarithmic`, `sCurveSigmoid`, and IEC 61672 A-weighted `equalLoudnessContour`) alongside an attack/release dB-domain dynamic compressor to produce beat-accented `HapticTransientFrame` sequences.

### 4. Headless CLI & JSON Benchmark Harness (`shakeandsound-cli`)
Run deterministic kinematics simulations, procedural audio synthesis, WAV file generation, tempo/haptic curve evaluation, and subsystem throughput benchmarks from the terminal:

```bash
# Check CLI version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run shakeandsound-cli --version

# Run 3-axis gravity isolation and shake pattern recognition (JSON output)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run shakeandsound-cli analyze-motion --pattern double-tap --json

# Synthesize a 330 Hz waveform, verify vDSP F0 pitch recovery, and export 16-bit PCM WAV
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run shakeandsound-cli synth --waveform sine --freq 330 --duration 0.15 --output /tmp/tone330.wav --json

# Estimate tempo and evaluate adaptive sigmoid haptic response curves at 128 BPM
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run shakeandsound-cli tempo-curve --bpm 128 --curve sigmoid --json

# Execute the full DSP verification and throughput benchmark suite
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run shakeandsound-cli benchmark --iterations 25 --json
```

---

## Core Subsystems

### 1. Multi-Modal Physical Seismograph (`SeismographService`)
- **Sensor Fusion:** Synthesizes low-frequency acoustic vibrations transmitted through the Mac chassis with hardware keystroke events, trackpad hover vectors, and window drag kinematics.
- **PGA & STA/LTA Trigger Detection:** Calculates real-time Peak Ground Acceleration (PGA) in milligravity ($mg$) and Short-Term Average to Long-Term Average ($STA/LTA$) energy ratios alongside `MotionKinematicsEngine` pattern classification.
- **Helicorder Canvas:** Renders a continuous, real-time seismogram canvas with adjustable sensitivity and persistent state retention across application tab transitions.

### 2. High-Performance Digital Signal Processing (`AudioWaveformEngine`)
- **Buffer Stream Pipeline:** Direct tapping of hardware input nodes providing 1024-sample PCM buffers at native sample rates (44.1 kHz / 48 kHz), plus offline buffer analysis via `AudioWaveformEngine.analyzeSamples`.
- **Spectral & Pitch Analysis:** Uses `vDSP` RMS calculation, 16-band energy decomposition, spectral centroid estimation, and autocorrelation $F_0$ pitch tracking with Voice Activity Detection (VAD).

### 3. Sound Classification & Artifact Suppression (`AudioClassifierService`)
- **SoundAnalysis Integration:** Utilizes Apple's `SNAudioStreamAnalyzer` to classify environmental audio streams in real time and flag non-speech artifacts (coughing, throat clearing, sneezing, keyboard typing, ambient clatter).

### 4. Bilingual Transcription & Voice Biometric Diarization (`SpeechTranscriptionService`)
- **Zero-Delay Speech Recognition:** Streams raw PCM buffers directly into `SFSpeechRecognizer` for continuous Korean, English, and multilingual speech recognition.
- **Voice Biometric Diarization:** Differentiates speakers by tracking vocal fundamental pitch ($F_0$ in Hz) and acoustic profiles across conversation turns.

### 5. Multi-Engine Summarization (`SummarizationService`)
- **Cloud & On-Device Summarization:** Supports cloud transcript structuring via the Google Gemini REST endpoint (`gemini-flash-lite-latest` / `gemini-flash-latest`) as well as zero-network on-device extractive summarization powered by Apple's `NaturalLanguage` framework (`NLTagger`, sentiment scoring, lexical keyword ranking).

---

## Directory Structure

```
ShakeAndSound/
├── Package.swift                             # SwiftPM manifest for ShakeAndSoundCore, CLI, and Tests
├── CHANGELOG.md                              # Release history and version notes
├── ShakeAndSound.xcodeproj                   # Xcode macOS application project configuration
├── ShakeAndSound/
│   ├── MyApp.swift                           # macOS application entry point
│   ├── ContentView.swift                     # Main sidebar and studio interface
│   ├── SeismoView.swift                      # Seismograph and helicorder canvas
│   ├── SeismographService.swift              # Multi-modal physical shake detection service
│   ├── MotionKinematicsEngine.swift          # Gravity isolation, 3-axis kinematics, pattern classifier
│   ├── SoundVisualizerView.swift             # Waveform and spectrum visualizer views
│   ├── AudioWaveformEngine.swift             # Audio capture, vDSP spectrum, pitch tracking
│   ├── ProceduralAudioSynthesizer.swift      # Polyphonic audio synth, seismic sonification, WAVCodec
│   ├── TempoHapticCurveEngine.swift          # Onset BPM estimator, response curves, dynamic compressor
│   ├── ShakeAndSoundTelemetry.swift          # Version metadata and DSP benchmark verification suite
│   ├── AudioClassifierService.swift          # SoundAnalysis classifier and noise filter
│   ├── SpeechTranscriptionService.swift      # SFSpeechRecognizer and speaker diarization
│   ├── SummarizationService.swift            # Cloud and on-device transcript summarization
│   └── Assets.xcassets/                      # App icons, visual assets, and color sets
├── Sources/
│   └── ShakeAndSoundCLI/
│       └── main.swift                        # Headless CLI verification and JSON benchmark runner
└── Tests/
    └── ShakeAndSoundTests/
        └── ShakeAndSoundTests.swift          # Automated unit, property, and hostile-input test suite
```

---

## Building and Testing

### Running Automated Unit & Property Tests (SwiftPM)
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Command Line macOS Application Build (Xcode)
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ShakeAndSound.xcodeproj \
  -scheme ShakeAndSound \
  -configuration Release \
  -derivedDataPath /tmp/ShakeAndSoundDerivedData \
  build
```

---

## System Permissions

To enable live hardware sensing in the macOS application, macOS requires user authorization for:
- **Microphone Access (`NSMicrophoneUsageDescription`):** Required for real-time acoustic signal processing, sound classification, and physical chassis micro-vibration analysis.
- **Speech Recognition (`NSSpeechRecognitionUsageDescription`):** Required for streaming speech-to-text transcription.

---

## Author & License

Copyright (c) 2026 Jeong Hoon Kim. All rights reserved.

Licensed under the MIT License.
