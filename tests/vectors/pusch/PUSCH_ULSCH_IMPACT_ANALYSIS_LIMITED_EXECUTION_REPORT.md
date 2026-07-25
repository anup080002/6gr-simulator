# PUSCH/UL-SCH implementation and impact-analysis pack — limited execution report

**Generated:** 2026-07-24T14:45:29.489897+00:00  
**Pack root:** `pusch_ulsch_impact_codex_pack`  
**Purpose:** production remediation of the 12 PUSCH/UL-SCH findings, followed by controlled technical impact analysis.

## 1. Delivered scope

The combined Codex prompt contains the original production implementation closure plus a mandatory technical impact extension.

| Item | Count |
|---|---:|
| PUSCH/UL-SCH implementation findings | 12 |
| Base deterministic input rows | 487 |
| Base bounded expected rows | 480 |
| Impact-analysis families | 52 |
| Impact experiment definitions | 705 |
| Family-specific pairing contracts | 52 |
| Impact acceptance rules | 70 |
| Hard rules | 55 |
| Statistical rules | 7 |
| Diagnostic rules | 8 |
| Independent analytical-floor rows | 59 |
| Base production CSVs required | 20 |
| Base production PNGs required | 11 |
| Additional impact CSVs required | 16 |
| Additional impact PNGs required | 26 |
| Total production artifacts required | 73 |

The impact matrix spans 373 AWGN, 135 TDL and 197 CDL experiment definitions. It includes 111 connected-mode and 10 random-access definitions in addition to PHY calibration cases.

## 2. Implementability waves

| Wave | Families | Meaning |
|---|---:|---|
| `A_CORE_PUSCH_NOW` | 28 | Can be implemented and analysed directly while correcting the PUSCH/UL-SCH production chain. |
| `B_PUSCH_INTERNAL_DEPENDENCY` | 10 | Implement in this PUSCH phase after the named assignment/SRS/HARQ/covariance prerequisite is complete. |
| `C_CROSS_AREA_DEPENDENCY` | 14 | Experiment definition is ready, but execution depends on another physical procedure, RF, frame, timing, RA, or multi-user component. |

Wave-C experiment definitions are intentionally present now. They must not be executed using fake perfect timing, perfect covariance, scalar interference, configured SINR, an ideal PA in place of a nonlinear PA, or true-channel receiver inputs. During development they may be marked `blocked_dependency`; final completion requires the real dependency and a successful run.

## 3. Impact dimensions covered

The 52 families quantify, rather than merely enable, the following effects:

- exact UCI/UL-SCH bit ownership, CSI Part 1/2 capacity cost, beta-offset trade-offs, UCI-only detection, and two-codeword owner selection;
- TBS/base-graph/segmentation boundaries, LDPC iterations and LLR scaling;
- decoded DCI ownership, Type-1/Type-2 configured-grant latency and collision behavior, Msg3/MsgA uplink behavior;
- modulation, rank 1–8, one/two codewords, codebook/non-codebook operation;
- DM-RS density/type/length/ports, cross-port leakage, PT-RS phase tracking and overhead;
- CP-OFDM versus DFT-s-OFDM PAPR, PA-backoff sensitivity, frequency-hopping null/diversity/HARQ interactions;
- SRS quality, age, sounded bandwidth, RI/SRI/TPMI accuracy, perfect/measured/stale/fixed-precoder gaps and calibration error;
- open-loop and closed-loop power control, P_CMAX clipping, pathloss-estimate error, near-far and inter-cell externality;
- ZF/MMSE/IRC, covariance quality, HARQ combining and latency, MU-PUSCH, measured-SINR calibration and false-decode robustness;
- CFO, timing offset, phase noise, numerology/mobility, runtime/memory scaling, deterministic replay, factorial interactions and coherent end-to-end profiles.

## 4. Scientific controls

The pack separates three evidence classes:

1. **Hard correctness:** exact bits, REs, ports, state transitions, power equations, digests, and no-waveform negative behavior.
2. **Statistical effects:** Wilson or exact binomial intervals, McNemar paired error tests, paired bootstrap confidence intervals, effect sizes and Holm correction.
3. **Diagnostic effects:** valid measured results that may legitimately be beneficial, harmful, neutral or inconclusive.

The pairing contract prohibits unpaired fallback. Baseline and treatment trials must share payload, channel and noise streams unless the treatment intentionally changes that process. Missing, duplicate or control-mismatched pairs must fail or remain blocked; they cannot be silently analyzed as independent samples.

The pack deliberately does **not** contain golden BLER or throughput curves. Those values must be produced by the corrected MATLAB production chain. The supplied analytical floor is limited to exact arithmetic, identity, recurrence, energy, ownership and fail-closed relationships.

## 5. Executed checks in this environment

### 5.1 Base PUSCH vector-pack verification

```text
files=31
failures=0
```

### 5.2 Impact-pack verification

```text
families=52
experiments=705
pairing_contracts=52
rules=70
analytical_floor=59
csv_contracts=16
image_contracts=26
failures=0
```

### 5.3 Base artifact-verifier self-test

```text
valid synthetic set:    42 passed, 0 failed, exit 0
corrupted PNG hash:     41 passed, 1 failed, exit 2
corruption detected:    yes
```

### 5.4 Impact artifact-verifier self-test

```text
valid synthetic set:
    required experiments: 705/705
    required rules:       70/70
    required CSVs:        16/16
    required PNGs:        26/26
    failures:             0
    exit:                 0

injected corruption:
    failure: png_hash_mismatch:pusch_impact_uci_capacity.png
    exit:    2
```

### 5.5 Python compilation

```text
Python scripts compiled: 8
Compilation failures:    0
```

## 6. Current uploaded simulator result

The existing source-specific audit reports:

```text
Targeted defect signatures: 38 FAIL
Useful implementation foundations: 9 PASS
Current implementation phase: FAIL
```

The limited base execution suite reports:

```text
Total checks: 25
PASS:         22
FAIL:          2
BLOCKED:       1
```

The two failures are the expected pre-remediation source/artifact failures. The blocked item is production MATLAB execution.

### Current required artifacts

```text
Base PUSCH phase artifacts present:   0 / 31
Impact-analysis artifacts present:    0 / 42
Combined required artifacts present:  0 / 73
```

Existing generic simulator figures are not substitutes for the required PUSCH resource, UCI, DM-RS/PT-RS, transform/hopping, SRS/precoding, power-control, HARQ/receiver and impact figures.

## 7. Runtime limitation

Neither `matlab` nor `octave` is installed in this environment. Therefore, the following remain unexecuted and must be run by Codex on the pinned MATLAB/5G Toolbox release:

- production PUSCH/UL-SCH TX/RX and no-noise round trips;
- exact TS 38.212 UCI multiplexing/demultiplexing through production code;
- rank 1–8, two-codeword, DM-RS/PT-RS, transform-precoding, hopping and SRS-driven precoding campaigns;
- closed-loop power-control and actual waveform-power reconciliation;
- AWGN/TDL/CDL BLER and effect campaigns;
- all 705 impact experiments;
- all 36 production CSVs and 37 production PNGs;
- MATLAB figure-object semantic auditing.

The successful Python checks establish pack integrity and verifier behavior only. They do not establish that the current simulator passes the required waveform experiments.

## 8. Completion condition

Codex may report `COMPLETE` only when the base implementation phase and impact phase both pass, all 73 production artifacts are generated and verified, no mandatory operating point is incomplete or blocked, all 55 hard rules pass, and every statistical/diagnostic rule has a valid result or scientifically explicit `inconclusive` conclusion.
