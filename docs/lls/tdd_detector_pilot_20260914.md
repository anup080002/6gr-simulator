# TDD Format-0 detector development pilot

Status: implementation candidate; first runtime test pending. This is not a
qualified detector, a held-out campaign, a main integration pass or a 12 dB run.

The existing idle `work/shared-pusch-completion-20260914` checkout was safely
fast-forwarded to `3fa1399d` before adding this pilot. The full regression in
`sixgr_type2_runtime_20260913` remains untouched on `3fa1399d`.

`tests/runPUCCHDetectorPilot.m` consumes the explicit validation YAML. It runs
one shared physical owner per independent episode, with eight declared cases:
noise-only widths 1/2 and transmitted 0, 1, 00, 01, 10, 11. These transmitted
vectors are detector test inputs, never claimed as actual decoded DL outcomes.
Each PUCCH slot follows an actual SRS four slots earlier. The receiver receives
only a length/resource hypothesis and actual post-RF samples with the retained
SRS timing reference. Noise cases arm a receive-only window without preparing
a PUCCH TX. Actual prior SSB timing and SSB measurements are used; initial TAG
and common power information are explicitly preconfigured component inputs,
not full PRACH/RAR/SIB1 access qualification.

The 0.42 detector policy and 1% limit are unchanged. Pilot and qualification
are distinct: even flawless one-episode execution cannot become qualified.
Unavailable episodes are reported separately, not fabricated as RF rows, and
count as failures for the conservative family-adjusted confidence calculation.
Every completed case retains its actual pre/post-RF samples, all replay segments,
received timing, decoded payload/DTX and evidence hash. Exceptions retain the
partial state and original diagnostic. Root physical CSV rows contain only
actual receiver executions; case-summary rows are explicitly pilot accounting.

Next gates: pass this physical infrastructure pilot without bypassing any
timing or power-authority checks; diagnose signal-present errors; freeze a
development/model-selected YAML receiver policy; then use fresh held-out seeds
and the predeclared 600-episode/eight-case/family-alpha-0.05 design. Full-source
testAll, NR and result-integrity guards remain required for the new code.

Run via `scripts/run_server_testall.ps1 -Tests testPUCCHDetectorPilot` on a
clean frozen checkout; the emitted log identifies the complete pilot folder.

First run on b25b71c4 (`logs/testall_20260914T113257935Z_fd2eaefa`) failed
before PHY execution because the authored seed paths used internal `rf`
instead of scenario `rf_frontend`. The YAML mapping is corrected; missing
seed paths still fail loudly, and no randomness source is silently omitted.
