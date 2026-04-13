# 6G PHY LLS Framework Surfaces

Use this reference when a task adds or audits configurable coverage in the 6G PHY LLS framework.

## Non-Negotiable Architecture Rules

1. All scenario parameters live in configuration.
- No PHY parameter should be hardcoded in source logic, notebooks, tests, helper scripts, or CLI shims.
- Front-door execution should accept only:
  - config path
  - output directory
  - run tag
  - optional log level

2. One resolved config object drives the whole run.
- Every module should consume one validated resolved `ScenarioConfig`.
- No hidden environment-variable behavior switches.
- No hidden defaults that materially change simulation behavior.

3. Inheritance must be layered and explicit.
- The composition model should support:
  - global defaults
  - release or profile defaults
  - band pack
  - waveform pack
  - channel pack
  - MIMO or beam pack
  - reference-signal pack
  - AI or ML pack
  - impairment pack
  - energy-efficiency pack
  - scenario override
  - sweep or matrix override

4. Exact run provenance must be saved.
- Required artifacts:
  - raw input configs
  - resolved config after inheritance
  - schema validation report
  - simulator version and git hash
  - random seeds
  - environment summary

5. Validation is mandatory.
- Fail fast on invalid or contradictory config combinations.
- Error messages should name the field, the reason, the allowed values or range, and any violated dependency.

6. Every feature block must be configurable.
- No hidden defaults for waveform, coding, modulation, scrambling, interleaving, layer mapping, precoding, beamforming, DMRS, CSI-RS, SRS, PTRS, TRS, tracking RS, PDCCH, PDSCH, PUSCH, PUCCH, PBCH, PRACH, CSI acquisition, HARQ, receiver type, impairments, AI or ML models, or energy and complexity instrumentation.

7. Single-run and matrix-run execution are both first-class.
- Parameter sweeps should be native capabilities, not custom scripts.

8. Outputs must be both machine-readable and human-readable.
- At minimum support JSON, CSV or Parquet, images for major curves, report documents, and optional rich intermediate trace containers.

9. All baseline and candidate features must be individually switchable.
- NR-like benchmark blocks, candidate 6G blocks, AI or ML blocks, extra impairments, and debug traces should all be independently configurable.

10. Deterministic reproducibility is required.
- Seedable generators, deterministic evaluation mode, reproducible sweep ordering, and same-config reproducibility within numerical tolerance are expected surfaces, not optional niceties.

## Classification Contract

Every feature and scenario should carry an explicit research class:

- `baseline_benchmark`
- `agreed_starting_point`
- `study_item_candidate`
- `optional_research_experiment`

If the repo lacks a field for a new classification surface, add a generic YAML field rather than embedding the classification in MATLAB logic.

## Minimum Config Domains

These domains should be configurable through YAML catalogs, defaults, or scenarios rather than hardcoded in MATLAB.

### 1. Provenance and run intent

- Scenario ID
- Version
- Description
- Owner
- Scenario group
- Research-class tag
- Run scope
- Output profile
- Deterministic seed and Monte Carlo controls

### 2. Simulation control

- Link direction
- Duration, frames, slots, sweep grids
- Deterministic vs randomized execution
- Smoke vs validation vs sweep profiles
- Log level
- Save flags for CSV, MAT, images, logs, and snapshots

### 3. Carrier, bandwidth, and frame structure

- Center frequency
- Bandwidth
- SCS and numerology options
- Duplex mode
- CP type
- TDD pattern
- NSizeGrid / carrier sizing

### 4. Waveform and channel family

- CP-OFDM / DFT-s-OFDM
- Transform precoding
- AWGN / TDL-* / CDL-* family
- Concrete fading profile
- Delay spread
- Doppler
- Pathloss model
- LOS/NLOS flags
- Shadow fading
- Spatial consistency

### 5. Node and topology assumptions

- BS Tx/Rx chains
- UE Tx/Rx chains
- UE count
- RNTI allocation policy
- Cell identity inputs where relevant
- Multi-user execution model

### 6. MIMO and beamforming

- Tx/Rx antenna counts
- Layer count
- Precoder type
- Codebook type
- Reciprocity mode
- Beam count
- Beam sweep enablement
- Panel count
- Multi-panel or MTRP readiness
- Beam selection strategy

### 7. Reference and synchronization signals

- SSB
- PBCH / MIB / SIB1 benchmark hooks
- DMRS for PDSCH and PUSCH
- CSI-RS
- SRS
- PTRS
- TRS
- Tracking RS
- CQI / PMI / RI reporting

### 8. Control, data, and random access

- PDCCH enablement and blind-decode settings
- CORESET and search-space controls
- PDSCH modulation, MCS, layers, DMRS ports
- PUCCH format and payload assumptions
- PUSCH modulation, MCS, layers, transform precoding
- PRACH format, configuration index, preamble count, root sequence, ZCZ, thresholding

### 9. Coding and HARQ

- Data coding
- Control coding
- MCS table
- Decoder iteration limit
- HARQ enablement
- HARQ process count
- RV sequence
- Feedback timing
- Combining mode

### 10. Impairments

- CFO
- Phase noise
- IQ imbalance
- PA nonlinearity
- Timing offset
- ADC and DAC quantization

### 11. Candidate 6G and AI-assisted features

- AI/ML enablement
- Mode
- Use case
- Model path and descriptor
- Runtime and FLOP budgets
- Confidence logging
- Fallback policy
- Energy-awareness knobs

Candidate features must stay explicitly gated and tagged. Do not fold them into the benchmark path silently.

### 12. Result and KPI controls

- Which block-level CSV tables are emitted
- Which images are emitted
- Which MAT bundles are emitted
- Which summary plots are emitted
- Which manifest and snapshot files are written
- Block-specific KPI thresholds and acceptance rules
- Whether Parquet, HDF5, or NPZ trace containers are emitted where supported

## Expected Output Structure

For a meaningful LLS run, preserve structured outputs under the run folder:

- `meta/`
- `reports/csv`
- `reports/mat`
- `reports/image`
- `air_interface/csv`
- `air_interface/image`
- `air_interface/logs`
- `air_interface/mat`
- `control/csv`
- `beamforming/csv`
- `beamforming/image`

Add more block folders only when they represent real output families. Do not create duplicate folder concepts such as both `fig/` and `image/` for the same artifact type.

Also preserve run-provenance artifacts alongside outputs:

- `meta/input_configs/`
- `meta/resolved_config.json`
- `meta/resolved_config.yaml`
- `meta/schema_validation_report.json`
- `meta/environment_summary.json`
- `meta/seeds.json`

## Implementation Order

When adding a new configurable capability:

1. Update YAML catalogs, defaults, and scenario fragments.
2. Update schema and validation.
3. Map resolved YAML into internal config.
4. Update generic runners or PHY execution code if a real new capability is needed.
5. Extend manifests, reports, and KPI exports.
6. Add regression tests.

## Hardcoding Red Flags

Treat these as problems unless they are truly fixed implementation logic:

- Scenario-specific MCS, layer, beam, or antenna values buried in MATLAB
- Hardcoded allowed-value lists that duplicate YAML catalogs
- Silent clamping from configured multi-layer or multi-user requests to simpler behavior
- Result writers that assume a block is always present
- Research feature classification inferred from scenario name instead of config
