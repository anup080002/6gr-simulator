# Consolidated candidate: receiver-owned PUCCH extraction — 2026-09-13

Status: staged, unapplied, uncommitted, not pushed, and NOT runtime-validated.
The 12 dB scenario remains unqualified. All three existing full suites are live
against unchanged source checkouts and do not validate this staged source.

Base revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.
Patch: pending_consolidated_receiver_fields_20260913.patch.
31 files, 1,409 insertions, 117 deletions. Whitespace-strict git apply --check
passed against the base checkout; this is not a MATLAB execution result.

## Integration defect addressed

CoupledTruthRuntime.observePUCCHFeedback reparsed the received wire bits using
UCIReportSerializer.serialize(connected.Report), where connected.Report is the
transmitter's report. It also required decoded field lengths to match the TX
payload before declaring receiver usability. That would override an independent
receiver hypothesis even though runPUCCHWaveformTrial already retained canonical
receiver-owned field boundaries and expected lengths.

The staged coordinator now calls extractPUCCHReceiverFields. The helper consumes
the actual Receiver.DecodedSequence1/2 and DecodedFields, checks their agreement
with the trial's receiver-field mirror, validates binary values before casting,
and checks lengths against receiver-owned count metadata. Padding stays outside
the delivered information bits. Missing metadata and inconsistent fields fail
loudly; incomplete decoded fields remain incomplete and layoutOK=false.

Receiver usability no longer depends on transmitter payload length. CSI decode
presence uses receiver-owned CSI lengths. Transmitter content/length comparisons
remain scoring information, not a reason to redefine decoded field ownership.
No PHY waveform, detector, CRC, threshold or noise/power setting changes here.

testPUCCHReceiverFieldAuthority is registered in testAll. Its declared unit
fixtures cover HARQ/SR/CSI/padding, contradictory TX serialization and scoring
aliases, inconsistent receiver fields, fractional bit rejection, missing
metadata, empty reception and incomplete CSI. The test has NOT executed.

## Important unfinished integration boundary

The helper validates receiver-output consistency; it does NOT prove that the
receiver context was independently constructed from the gNB schedule or that
any PHY execution occurred. Normal shared PUCCH completion still needs its
independent receive hypothesis and gNB bit-to-TB mapping commit. The existing
normal coordinator still contains UE pending-row association; PUSCH needs its
corresponding independent receive/mapping path. Combined CSI/SR hypotheses and
their calendars must be installed from configuration, not derived from actual
transmitted payloads. This patch does not claim those issues are fixed.

Do not qualify the integrated run or deploy this as a validated HARQ baseline
until those mappings and their integrated tests are complete. The earlier
receiver-only missing-DCI mapping candidate remains a narrower tested path.

## Consolidation and remaining validation

This includes all 29 files of the previous consolidated proposal, including
PRACH. Only CoupledTruthRuntime and testAll change among them; the receiver-field
helper and its test are added. Older source stages, patches and evidence bundles
remain preserved. This patch supersedes pending_consolidated_all_20260913.patch
and the older overlapping proposals; do not stack them on top of one another.

Required: execute the new leaf test, rerun the independent PUCCH trial/CRC cases
through this extraction boundary, finish and test normal shared PUCCH/PUSCH
mapping, and run the final-source repository/skill-required testAll,
NR/config/strict/grant/E2E/export/config-driven scenario tests. No new MATLAB
process was launched while the three requested full suites hold most memory.

False/missed ACK qualification, CSI measurement/report timing/calendar closure,
DL timing/CFO/EVM fixtures, all integrated measurement/output checks, 12 dB and
the same-chain sweep remain open. The later long all-impairments/full-feature
study is still part of the objective.
