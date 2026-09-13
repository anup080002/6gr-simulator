# Independent PUCCH trial receive boundary — 2026-09-13

Status: candidate tests passed on MATLAB R2026a; NOT applied, committed, or integrated with normal shared scheduling. No 12 dB qualification is claimed.

Base revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.

## Change

The trial completion adapter can now receive a separately typed gNB allocation and length-only context through ReceivedContext.GNBReception. It rejects a TX assignment, extra payload fields, and a context whose digest differs from the allocation's bound context. The physical receiver consumes that allocation, not the prepared transmitter's assignment. Prepared TX data remains available separately for waveform provenance and scoring.

Receiver field extraction and expected HARQ/SR/CSI lengths are exported from the receive context and actual receiver. CRC applicability, per-codeblock errors and CRC bit count come from actual receiver decoding. Transmitter CRC metadata is retained under separate Transmitter-prefixed fields. This incorporates the native UCI CRC correction documented in uci_crc_evidence_20260913_01.zip.

Legacy calls without a gNB hypothesis remain explicitly transmitter-coupled. Therefore this adapter change alone does not close the normal shared HARQ path.

## Executed evidence

- Attempt 01: four actual coded format-2 connector cases passed, exit 0.
- Attempt 02: the four cases passed again after correcting receiver channel-estimate provenance to use the receive format. Two retained shared-stream format-0 hypotheses also passed, exit 0.
- TX/RX expected lengths 3/3, 3/12, 12/3, 12/12 all reproduced the direct receiver-only API exactly, excluding wall-clock profiling fields.
- 3/12 remained detected but failed the actual receiver CRC. 12/3 correctly reported receiver CRC as not applicable despite the TX having a CRC. Matching 12/12 recovered HARQ=2, SR=1, CSI Part 1=9 bits exactly.
- Altering injected variance and covariance metadata did not change actual receiver outputs. Completion did not advance the random generator or regenerate transmission/noise.
- Format-2 cases are explicitly declared AWGN/analytic-connector component fixtures at 34 dB. They are not the requested integrated 12 dB scenario, physical pathloss validation, or scheduled missing-DCI evidence.
- Retained format-0 cases use actual shared post-RF IQ and an actual prior received SRS timing reference from docs/lls/evidence_20260913/pucch_baseline_signal_04/received_pucch.mat. Prescribed one-/two-bit hypotheses reproduce direct reception. The unchanged 0.42 threshold is selected by this resource's two OFDM symbols, not payload bit count. These two hypotheses are not false/missed-ACK statistical qualification.

## Patch and integration

pending_pucch_independent_trial_and_crc.patch passes git apply --check --whitespace=error against the base revision. It includes three production files, four permanent tests and their testAll registration (eight files total). It SUPERSEDES pending_uci_crc_native_authority.patch: do not apply both. Older CRC evidence and its patch are preserved, not discarded.

The staged permanent tests differ from the executed candidate tests only in production function/class references, default output-directory creation under logs, and console labels. Those permanent tests and the final production source still require execution after integration. Do not add either integration-stage directory to the path of a running suite.

Remaining normal-runtime integration: derive gNB receive obligations from actual transmitted DL schedules and installed CSI/SR reporting calendars; bind them through preparation/completion; use receiver-owned field lengths rather than TX serialization; map and commit HARQ by scheduled transmission identity rather than UE row ordinal; complete PUSCH handling and CSI consumers. Existing completeSharedPUCCHFeedbackRuntime still calls the legacy path until those obligations and consumers are wired.

All three pre-existing full suites remain running and their source checkouts are unchanged. They do not validate this patch. After integration, run testAll and all applicable NR/config/strict/grant/E2E/export checks on the final revision, followed by the integrated measurement and 12 dB gates. Both older suites have separately recorded the mobile two-UE no-progress failure; the latest suite is not yet terminal.
