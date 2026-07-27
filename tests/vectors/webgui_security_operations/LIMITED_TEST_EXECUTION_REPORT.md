# WebGUI security, operations, YAML, and dashboard pack — limited execution report

## Current source result

The current repository fails this phase. It contains both the old single-file dashboard and the new React/FastAPI stack. The new API and WebSocket routes have no centralized authentication or authorization; the edited YAML text is not the configuration that MATLAB runs; the result API hard-codes a few artifacts; and the old stack retains open/plaintext/default-credential behavior.

## Static and pack checks executed

```text
PASS:    5
FAIL:    6
BLOCKED: 2
```

Key pack facts:

```text
Findings:                    12
Catalog parameters mapped:   2158
Artifact contracts indexed:  1197
DUT visual definitions:      88
Visual archetypes decoded:   8
Current FastAPI routes found: 23
Old dashboard routes found:   29
Active scenario YAML files:   82
Legacy scenario YAML files:   9
```

## What was not executed

MATLAB and the 5G Toolbox are unavailable in this environment, so the canonical AWGN and geometry scenarios could not be launched through a corrected WebGUI. Frontend dependencies are not installed, so the TypeScript build and Playwright tests were not executed. These are recorded as BLOCKED and remain mandatory Codex acceptance gates.

## Attached images

All eight supplied images decoded successfully and are copied under `visual_references/`. The catalog marks them as design archetypes only. They cannot be included in a run manifest or used as simulator evidence.

## Current defects confirmed

- old and new WebGUI stacks coexist;
- new routes and WebSocket are unauthenticated;
- old stack defaults to open access and has plaintext/default credential paths;
- public development launch uses `--reload`;
- active and legacy scenario roots are mixed;
- raw YAML edits are not executed;
- run state is in memory;
- run-directory discovery uses substring matching;
- result/artifact discovery is hard-coded;
- no all-domain measured-results dashboard exists.

The generated Codex prompt requires production edits, tests, deployment smoke, real MATLAB runs and old-stack deletion after parity.
