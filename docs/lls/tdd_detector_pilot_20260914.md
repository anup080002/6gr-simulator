# TDD Format-0 detector development pilot

Status: scheduling pilot passed; power-correct rerun pending. This is not a
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

The c5fcba34 rerun (`logs/testall_20260914T113622405Z_7eb9e80d`) recovered
SSB timing but failed the reference-measurement filter because the new pilot
row omitted ServingCell. It now retains the actual broadcast serving-cell
identity and uses normal startSlot initialization for the sweep clock. SSB
receiver evidence is saved before acceptance/publication, and exceptions emit
their original JSON diagnostic before the larger partial-state MAT save.
The pilot remains incomplete; no physical case or qualification pass is claimed.

The 3956628c rerun (`logs/testall_20260914T114125650Z_601f8af2`) passed
the earlier SSB publication boundary, then failed with
`WAVEFORM:CommittedTransmission` while queueing SRS. The pilot had waited
until the nominal SRS slot, although the received timing/TA authority places
the waveform capture start before that boundary. SRS is now prepared in the
preceding slot using the target slot's carrier timeline, with an explicit
assertion and sample-clock log proving preparation precedes its actual TX
start. The production committed-interval guard, timing authority, waveform,
power and detector threshold are unchanged. Rerun acceptance is still pending.

The 9982c815 rerun (`logs/testall_20260914T114707484Z_29190359`) passed
all eight actual noise/signal cases in 578.75 seconds, with zero observed case
errors and launcher exit 0 on unchanged clean source. Actual evidence is in
`logs/tp9434fe2c_208e_4082_8033_1d89a791590a`. The first SRS was queued at
sample 23040 before its actual transmit start 30620; all eight SRS preparations
passed the new causal guard. This verifies the scheduling repair only.

Concurrent source review found that the pilot's explicitly preconfigured
common SSB power used a literal 0 dBm instead of the configured broadcast
power contract. Those eight rows are retained as diagnostic evidence, not
power-correct acceptance or qualification. The pilot now resolves common
power from its scenario, verifies agreement against the actual prepared
broadcast contract, installs that declaration through the existing codec
fixture, and exports both contracts with explicit non-on-air provenance.
Measured SSB RSRP remains actual receiver output; no pathloss, gain, noise or
waveform power is substituted. Every refresh checks declaration consistency.
The corrected-source pilot, SSB power-contract test, full testAll and required
NR/result-integrity guards remain due.
