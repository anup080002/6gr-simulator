# Waveform Generation Pack — Limited Execution Report

## Scope

This report covers the uploaded simulator's waveform-generation layer: CP-OFDM, UL DFT-s-OFDM, stream continuity, windowing/WOLA, low-PAPR studies, multi-numerology composition, component-carrier composition, waveform power, PAPR and spectral validation.

## Current source result

```text
Static checks executed:              42
Targeted defect signatures:          34
Useful implementation foundations:   8
Current waveform phase:              FAIL
```

The strongest existing foundations are the Toolbox-backed OFDM modulator/demodulator, transform-precoding wrapper, OFDM noise-transform calibration, per-port waveform metric integration and native PUSCH configuration.

The principal current defects include:

```text
implicit 2.5% Nfft windowing
nextpow2 Nfft fallback
same-Toolbox acceptance comparisons
hand-written low-PAPR CP-OFDM using Nsc-point IFFT and Nsc/16 CP
DFT followed by equal-size full-band IFFT
bandwidth and symbol-count clamps
unknown modulation default to 16QAM
silent MEX fallback
all-sample OFDM power fallback
config-only low-PAPR and 6G waveform candidates
no canonical stream, WOLA, multi-numerology, CC, PAPR or spectral engines
```

## Deterministic pack validation

```text
Manifest files:              29
Protected deterministic rows:8391
Capability rows:             180
Impact families:             64
Impact experiments:          768
Matched pairs:               384
Acceptance rules:            96
Vector verifier exit:        0
```

The vector pack uses no MATLAB or 5G Toolbox to generate its bounded small-FFT, CP, unitary-DFT, pi/2-BPSK, WOLA, PAPR and coherent-tone analytical floors.

## Existing CSV and image status

```text
Existing CSV files inspected:      225
Rectangular CSV files:             224
Existing PNG files inspected:      40
PNG files decoded:                 40
Structurally nonblank PNG files:   40

Required waveform artifacts found:0 / 100
```

The existing figures are generic geometry/system plots and do not provide the 52 contracted waveform-specific images.

## Verifier self-tests

```text
Base complete synthetic set exit:       0
Base corrupted hash exit:                2
Impact complete synthetic set exit:      0
Impact corrupted hash exit:              2
```

Both verifiers accept a complete internally consistent artifact set and reject intentional PNG-hash corruption.

## Runtime limitation

```text
MATLAB available: False
Octave available: False
Relevant existing MATLAB tests inventoried: 476
```

No production MATLAB waveform was executed here. The MATLAB phase, BLER campaigns and production images remain mandatory and are marked blocked rather than passed.
