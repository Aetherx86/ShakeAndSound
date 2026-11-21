# Changelog

All notable changes to `ShakeAndSound` are documented in this file.

## [0.2.0] - 2026-11-20

### Added
- **DSP Motion Kinematics & Gesture Pattern Recognition (`MotionKinematicsEngine`)**:
  - Dual-stage gravity isolation using a first-order low-pass IIR filter to track static 3-axis tilt vectors (`isolatedGravityMg`) and a DC-blocking high-pass filter to extract pure dynamic linear acceleration (`linearAccelerationMg`).
  - Real-time 3-axis jerk derivation (`jerkMgPerSec`), leaky velocity integration (`velocityEstimateMmPerSec`), and geophysical Arias Intensity integration (`ariasIntensityMmPerSec`).
  - Sliding-window zero-crossing rate (ZCR), crest factor, autocorrelation dominant oscillation frequency, and inter-peak valley separation analysis.
  - Deterministic classification of physical kinetic regimes (`ShakePatternKind`: `idle`, `micro_tremor`, `single_tap_impact`, `double_tap_impulse`, `rhythmic_lateral_shake`, `seismic_shear_wave`) integrated into `SeismographService`.
- **Procedural Polyphonic Audio Synthesis & RIFF/WAVE Codec (`ProceduralAudioSynthesizer`, `WAVCodec`)**:
  - Polyphonic procedural waveform synthesizer supporting `sine`, `triangle`, `sawtooth`, `square`, `white_noise`, and `seismic_fm` oscillators with chirp frequency sweeps, ADSR envelopes, and soft-knee `tanh` limiting.
  - Seismic-to-audio sonification (`sonifySeismicTrace` and `SeismographService.exportRecentSeismicSonificationWAV`) mapping dynamic PGA and STA/LTA energy ratios into frequency-modulated audio buffers.
  - Hardware-independent `vDSP` acoustic feature extraction (`ProceduralAudioSynthesizer.analyzePCM` and `AudioWaveformEngine.analyzeSamples`) with parabolic lag interpolation for sub-sample autocorrelation pitch ($F_0$) recovery.
  - Standards-compliant 16-bit Little-Endian Linear PCM RIFF `.wav` encoder and 16-bit/32-bit float decoder (`WAVCodec`) with chunk validation and malformed container rejection.
- **Beat/Tempo Synchronization & Adaptive Haptic/Audio Curves (`TempoHapticCurveEngine`)**:
  - Positive spectral/energy flux onset detector with adaptive local thresholding, refractory debouncing, and median-clustered inter-onset interval (IOI) BPM estimation (`40..220 BPM`).
  - Monotonic transfer curves (`linear`, `exponential`, `logarithmic`, `sCurveSigmoid`, and IEC 61672 A-weighted `equalLoudnessContour`) paired with a stateful attack/release dynamic range compressor and beat-aligned haptic transient frame generator.
- **Headless CLI Verification & JSON Benchmark Harness (`shakeandsound-cli`, `ShakeAndSoundTelemetry`)**:
  - Swift Package Manager manifest (`Package.swift`) exposing `ShakeAndSoundCore`, `shakeandsound-cli`, and the `ShakeAndSoundTests` automated test suite alongside the Xcode application project.
  - CLI subcommands (`analyze-motion`, `synth`, `tempo-curve`, `benchmark`) with structured `--json` output and WAV file export.
- **Hostile-Input Hardening & Automated Test Suite**:
  - Comprehensive sanitization against `NaN`, `+/-Infinity`, subnormal values, extreme acceleration outliers, invalid sample rates, and truncated RIFF chunks across all DSP pipelines, verified by 19 automated unit and property tests.

## [0.1.0] - 2026-11-08

### Added
- Native macOS SwiftUI workstation combining chassis seismometry (`SeismographService`), `AVAudioEngine` + `Accelerate` vDSP spectrum analysis (`AudioWaveformEngine`), `SoundAnalysis` artifact suppression (`AudioClassifierService`), bilingual `Speech` transcription with pitch-based speaker diarization (`SpeechTranscriptionService`), and conversation summarization (`SummarizationService`).
