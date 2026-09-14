# TDD Format-0 detector development pilot

Status: scheduling pilot and repaired SSB power-contract test passed separately;
the detector pilot on the repaired power source and final regression remain due. This is not a
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

## Actual-sample power mismatch diagnosed on cd4ea4a1

Run `logs/testall_20260914T115858921Z_46e68901` returned launcher exit 1:
the pilot executed eight cases without observed errors (589.98 s), but
`testSSBPowerReferenceContract` failed (40.22 s). Actual SSS EPRE was
-54.4141866723 dBm against a 5 dBm declaration. Neither the pilot pass nor
agreement between its two metadata contracts closes this failing sample check.

Root cause: the inherited canonical configuration is FIXED_SNR_SWEEP with
configured_snr_is_link_authority=true. `applyPowerContext` correctly retains
the normalized IFFT samples without device-budget scaling, but
`resolveSSBPowerContract` still derived SSB power from the unapplied 30 dBm
budget. With 300 subcarriers and Nfft=512, that contract introduced
5 - (30 - 10*log10(300)) = -0.228787452803374 dB relative SSB offset.
The unscaled unit-tone sample reference is -20*log10(512) dBm, predicting
-54.41418667231999 dBm, within 2e-11 dB of the failing diagnostic.
This is not receiver noise or a loosened floating-point tolerance.

Repair: the existing quantized-full-BWP policy now resolves its base from the
canonical integration mode. Physical mode retains the device budget. Normalized
mode measures useful-sample power of a deterministic unit-RE IFFT calibration,
then quantizes SSB EPRE in that declared sample-unit reference. It does not apply
a device budget, rescale received measurements, change configured Es/N0, or
change detector thresholds. Calibration is not counted as an air-interface
trial. Normalized contracts explicitly deny a physical-device-power claim and
leave the unapplied device-budget field unavailable. Explicit absolute SSB
power is rejected in normalized mode. The existing SIB1 integer range remains
unchanged; a unit-reference configuration outside it fails, not clips.

The absolute-power test now has an explicit geometry/physical-power YAML
fixture; its original 30/33 dBm, actual-SSS and received-SIB1 assertions remain.
Added normalized checks verify that changing an ignored device budget changes
neither the normalized declaration nor actual SSS EPRE, and check actual SIB1
recovery and configuration-resolution idempotence. Both this test and the
detector infrastructure pilot are now registered in `testAll`; neither was in
that full-suite list previously. Their new-source runtime results are pending.

References: the [OFDM API](https://www.mathworks.com/help/5g/ref/nrofdmdemodulate.html)
defines the matching modulated/demodulated grid, with
[sample-rate/FFT configuration](https://www.mathworks.com/help/5g/ug/configure-ofdm-sample-rate-and-fft-size.html).
The integer SIB1 power field is constrained by
[TS 38.331](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.06.00_60/ts_138331v180600p.pdf).
The numerical mismatch above comes from local source and executed evidence,
not from an inferred compliance result.

The first cba54e24 power rerun (`logs/testall_20260914T121318907Z_a8a0058f`)
failed during configuration in 21.58 s: the new physical-mode fixture still
inherited `connected_control_smoke`, which the catalog does not allow for
GEOMETRY_NETWORK. The fixture now explicitly selects the existing supported
`connected_network` subprofile. No mode-validation rejection is relaxed;
the power repair remains runtime-unverified at this checkpoint.

## Verified power-reference repair on 39442d61

`logs/testall_20260914T121519045Z_a28dc2ee` completed with launcher exit 0,
unchanged HEAD and a clean tracked tree before/after. The expanded
`testSSBPowerReferenceContract` passed in 74.38 seconds on R2026a Update 4.
Each of the following verified actual transmitted SSS EPRE for four beams
and recovered the same declaration through actual SIB1 waveform decoding:

| Mode | Authored device budget | Actual / decoded SSS EPRE |
| --- | ---: | ---: |
| Physical device-budget reference | 30 dBm | 5 dBm |
| Physical device-budget reference | 33 dBm | 8 dBm |
| Normalized IFFT sample-unit reference, not device power | 30 dBm (unapplied) | -55 dBm |
| Normalized IFFT sample-unit reference, not device power | 33 dBm (unapplied) | -55 dBm |

The original 1e-6 dB waveform agreement tolerance was retained. Resolution
idempotence, physical/normalized provenance and explicit-absolute-power
rejection in normalized mode also passed. Receipts are preserved under
`docs/lls/evidence_20260914/ssb_power_reference_39442d61/`.

This closes the specific declaration-versus-emitted-sample mismatch, not
integrated receiver measurement/export closure. Earlier detector pilots used
the old mismatched declaration and remain diagnostic. The repaired-source
pilot is now a required full-suite entry; final-source testAll and explicit
NR/config/result-integrity guards, statistical detector qualification and
integrated 12 dB acceptance remain outstanding.

## 18:20 IST integration failure and candidate repair

The unfiltered `c5b21306` suite independently passed
`testSSBPowerReferenceContract` in 51.65 s. Its next detector pilot,
`logs/tp7786460f_0d72_41dd_a710_9d46ff062217`, failed before the first SRS:
`sixgr:truth:InvalidSSBPowerReference` in `bindSharedSSBPowerReference`.
The extended diagnostic and failure state are retained; the suite continues.

The declaration is now correctly -55 in the normalized IFFT sample mapping.
The first actual recovered RSRP is -54.38924037 in the same numerical mapping.
The partial-SSB pilot bypassed the full broadcast completion's normalized
power-domain labelling, published this value as absolute dBm, and the shared
binding attempted to use the difference as physical pathloss. Normalized
fixed-Es/N0 deliberately does not apply an absolute device/link budget.
The RA wrapper already had that distinction, but evaluated the shared
physical binding first, so its mode handling could be reached too late.

Candidate changes, not yet runtime-qualified:

- `bindSharedSSBPowerReference.m`: explicitly authored normalized mode marks
  absolute power reference as not applicable, clears stale pathloss and
  records configured occupied-RE Es/N0 authority. Physical nonnegative-loss
  rejection and SIB1 cell/epoch/knowledge validation are unchanged.
- `runPUCCHDetectorPilot.m`: retains actual partial-SSB power numbers in
  explicitly normalized IFFT fields, clears misleading absolute-dBm fields,
  and does not publish a fake absolute-RSRP row. Actual SSB acquisition,
  samples, SINR, timing and all numerical measurements remain in each MAT.
  No RX sample, detector threshold, seed, SNR, TA or noise value is changed.
- `testNormalizedSSBPowerAuthority.m`: reproduces the prior numerical case;
  checks direct and connected-UL binding, stale-value clearing, RA handling,
  missing/future SIB1 and unchanged physical/clock rejection. Registered in
  `testAll`. These are declared selector inputs, not physical episodes.
- The existing connected-SSB selector test now explicitly selects physical
  power mode for its original 5 - (-90) = 95 dB assertions. Its inherited
  scenario had changed to normalized mode. The original assertions and
  cases remain; it and the unchanged RA selector test are registered in
  the full suite alongside the new normalized-mode test. This is a fixture
  authority correction, not resumed FDD feature development.

Required next evidence: targeted new test and unchanged
`testSharedRAPowerReference`, then actual `testPUCCHDetectorPilot`, then
final-source full `testAll` and applicable NR/result-integrity guards. A pass
does not qualify the detector's original 12/1024 false-ACK result.

## Executed lossless-storage diagnostic, not an adopted writer

`logs/pucch_detector_diagnosis_20260914/lossless_archive_full_01/receipt.json`
records all 33 files of the historical cd4ea4a1 pilot, including configuration,
CSV, JSON and complete MAT evidence. Source size 1,750,814,187 bytes;
128-MiB-window Zstandard archive payload 168,276,338 bytes (90.39% reduction).
Every file was decompressed, length/SHA-256 checked against the source, and
the source was rehashed unchanged. Compression took 16.14 s total; stream
restoration plus hashing took 10.94 s, excluding the additional audit reads.
No source evidence was deleted or changed and no RF episode was added.

This proves a byte-exact storage option, not a PHY speedup or deployed
archiver. The 600-episode storage extrapolation is about 94.03 GiB of archive
payload, excluding receipts, scratch space and differing future outcomes.
The previous roughly 98-hour unoptimized PHY/pilot-duration estimate is not
replaced by the compression duration. Archive integration, dependency setup,
restoration workflow and failure/corruption tests remain necessary before
adoption. The original evidence and earlier failed diagnostic attempt remain
preserved. Script SHA-256:
`5d33f9fc88fe410fdb70b0bb61a14b01b18e495cda92e4cb0621a3727fc1ea85`.

## Normalized PUCCH materialization follow-through

Review after `a637bc16` found the next consumer still requiring a physical
pathloss: `PUCCHConfigBuilder.localPower` enforced measured absolute power
even for the explicitly normalized mode. `PUCCHTransmitter` then applied an
absolute target, which `preparePUCCHTransmitWaveform` undid using its recorded
linear scale. Thus merely correcting SSB binding was insufficient to make
the pilot's complete normalized transmit path valid.

The follow-on candidate introduces an explicit normalized variant of the
typed power-control state. It retains resource/numerology and unit occupied-RE
authority; absolute P0, pathloss, target power, PCMAX and headroom are NaN,
not invented zero values. Unapplied YAML power-control configuration is
retained separately. The transmitter emits its original generated IFFT
without an apply/undo absolute-power pair. The transmit boundary rejects
mixing a normalized TX with a physical configuration or a non-unit recorded
TX scale. Existing explicit physical-TX-to-normalized-reference replay is
still supported using its recorded scale, not receiver-derived scaling.

`testPUCCHNormalizedMaterialization` checks actual generated IFFT equality,
independence from unapplied absolute calibration, absent absolute metrics,
mode-mismatch/forged-state rejection and the retained physical requirement
for a measured pathloss. This is TX-only evidence, not a detector episode.
The existing physical resource, planning and measured-power fixtures now
explicitly select the physical mode; original physical assertions remain.
Normalized CSV checks now require unavailable absolute quantities instead
of requiring a manufactured unapplied power target.

No detector threshold, noise level, statistical gate or episode count has
changed. These changes still need runtime verification. At 18:29 IST both
old suites were live, and free physical RAM was below the 2,097,152 KiB launch
gate. No third MATLAB was launched and no live source was edited.

## 5084694c physical pilot PASS; fixture follow-up

The memory gate admitted the focused batch at 18:41 IST. It completed on
unchanged, clean `5084694c`, with eight passes and one fixture failure:
`logs/testall_20260914T131105593Z_e249b716`. Its launcher exit is 1 and the
whole batch is not relabelled as passed.

`testPUCCHDetectorPilot` passed in 717.32 s. All eight declared noise/signal
cases completed with zero observed event errors; actual received timing,
independent reception and full evidence are retained at
`logs/tpd658d619_5813_43bd_ac91_f97af303ac4d`. Both noise-only metrics were
below the unchanged 0.42 threshold. This closes the pilot's execution path,
not statistical detector qualification or integrated 12 dB acceptance.

The seven other passing tests were normalized PUCCH materialization,
connected SSB physical authority, shared RA authority, legacy normalized
transmit reference, resource/numerology power vectors, planning without
power, and measured physical PUCCH power control.

The failing `testNormalizedSSBPowerAuthority` discarded the updated state
returned by `applyUserContext`, then accessed its original unpopulated
large-scale ledger. Its equality assertion now uses the returned state and
actual selected serving cell. No propagation value or assertion tolerance
was changed. The remaining assertions in that test require a fresh rerun.
