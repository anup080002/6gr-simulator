# Validation, Statistics, Evidence and Publication Gates
## Limited execution and current-source report

## Scope

This report covers the current uploaded simulator source and the independent implementation pack for the 28 validation/statistics/evidence/publication findings.

It does not claim that the MATLAB production simulator has passed the phase.

MATLAB and Octave are unavailable in this execution environment.

## Pack integrity

```text
Prompt lines:                  2206
Findings:                     28
Independent manifest files:   33
Independent manifest rows:    2149
Vector-verifier checks:       862
Vector-verifier failures:     0
Capability rows:              168
MATLAB tests planned:         85
Impact families:              64
Impact experiments:           768
Matched impact pairs:         384
Impact acceptance rules:      96
Contracted production assets: 100
```

Base artifact-verifier self-test:

```text
complete synthetic set: exit 0
injected PNG hash mismatch: exit 2
```

Impact artifact-verifier self-test:

```text
complete synthetic set: exit 0
injected PNG hash mismatch: exit 2
```

## Current source result

```text
Static checks:                 60
Targeted defects detected:     48
Useful foundations detected:   10
Current result:                FAIL
```

Confirmed defects include:

```text
max_tb_per_point_reached versus max_trials_reached token mismatch
hard-coded 95 percent confidence and z value
DUT summary copied to reference CSV
reference-comparison gate checks table presence
fail-open curve metric helper
optional measured SINR
configured/reconstructed runtime evidence
circular expected/applied comparisons
fixture/static release anchors mixed with runtime acceptance
import-time MATLAB R2024a requirement
invalid source YAML
absence of one canonical schema/enum/oracle/provenance/join/merge engine
```

Useful foundations include:

```text
hierarchical deterministic seed helper
campaign task keys and task seeds
receiver-measured post-equalization SINR fields
artifact audit entry points
publication gate integration point
fixed-link campaign task planning
run-class metadata
existing JSON schemas
large MATLAB and Python test corpus
reference sweep reader integration
```

## Current Python collection result

```text
Command:            pytest --collect-only -q
Exit code:          2
Tests collected:    17
Collection errors:  40
```

The primary causes are:

```text
apps/lls_web_dashboard.py raises FileNotFoundError during import when
C:\Program Files\MATLAB\R2024a\bin\matlab.exe is absent

several tests import tests._actual_lls_test_helper while the tests
package is not importable under the current collection environment
```

## Current YAML result

```text
YAML files checked:               198
Source YAML failures:             1
Generated/baseline YAML failures: 2
```

The source failure is:

```text
simulator/configs/defaults/lls_result_output_catalog.yaml
```

It contains unquoted colon-bearing values inside flow mappings.

## Existing CSV and image result

```text
Existing CSV files:       225
Rectangular CSV files:    224
Malformed CSV files:      1

Existing PNG files:       40
Decoded/nonblank PNGs:    40
```

The one malformed CSV is an existing `phase7_truth_gates.csv` artifact.

The existing PNGs are generic simulator plots; none of the 52 contracted validation figures is present.

## Required production assets

```text
Base phase:
    32 CSVs
    22 PNGs

Impact phase:
    16 CSVs
    30 PNGs

Total:
    48 CSVs
    52 PNGs
    100 artifacts
```

Current contracted assets present:

```text
0 / 100
```

## Runtime limitation

```text
MATLAB available: false
Octave available: false
```

Therefore:

```text
no corrected production MATLAB campaign was executed
no full MATLAB test suite was executed
no canonical runtime scenario was executed
no production validation CSV or PNG was generated
```

Runtime unavailability is `BLOCKED`, never `PASS`.
