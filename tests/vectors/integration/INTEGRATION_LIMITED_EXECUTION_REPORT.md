# Limited execution report — two-mode integration pack

## Scope

The pack has been generated for the next integration phase after implementation of frame/grid, waveform, PHY channels, control/initial access, measurements/link adaptation, MIMO/beamforming, channel/RF, MAC/HARQ, protocol, validation and WebGUI/release work.

## Pack checks

```text
Findings: 32
Acceptance rules: 120
MATLAB integration tests specified: 100
Actual-run matrix rows: 25
Cross-mode equivalence vectors: 64
Negative vectors: 60
Required CSV contracts: 56
Required PNG contracts: 40
Pack verifier exit code: 0
```

## Runtime limitation

```text
MATLAB available: False
Octave available: False
Actual MATLAB integration runs executed here: 0
```

The latest post-remediation repository was not attached to this turn, and this environment does not provide MATLAB. Therefore no claim is made that the live integrated code passes, or that the required fixed-SNR/geometry result artifacts exist. The Codex prompt makes actual MATLAB runs, fresh result inspection, cross-mode equivalence, full regressions and artifact verification mandatory before `COMPLETE`.

## What was verified here

- all pack files exist;
- finding/rule/test/vector counts are consistent;
- artifact contracts have unique paths;
- the dashboard visualization catalog covers every required image;
- verifier scripts compile and the pack verifier passes.

## Required next evidence

Codex must return real run IDs, exact resolved YAML hashes, actual output folders, test logs, CSV row counts, measured numerical results, PNG dimensions/hashes and the artifact-verifier exit code.
