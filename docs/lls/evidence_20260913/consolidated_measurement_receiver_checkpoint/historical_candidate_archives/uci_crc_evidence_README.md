# UCI native CRC authority candidate — 2026-09-13

Status: isolated candidate tested; NOT integrated, committed, or qualified for the 12 dB scenario.

Base revision: 8412775e52ffba94f2cb9cb6dc9779d6ac54192a.

The production UCI decoder discarded the second output of nrUCIDecode and returned CRCPassed=true unconditionally. This candidate preserves the actual per-codeblock errors and requires all CRC-protected blocks to pass. Payloads without a CRC retain a neutral boolean gate but explicitly report CRCApplicable=false and CRCStatus=not_applicable. Decoder bits are not modified to match expected payloads.

Evidence obtained with MATLAB R2026a:

- Native decoder comparison: 11 payload lengths; seven corrupted-input cases exposed the old unconditional pass. Actual native bits and CRC-error vectors were preserved.
- Actual format-2 PUCCH waveform comparison: desired RNTI passed; wrong-RNTI waveform was detected but failed CRC. The correction did not change decoded bits, detection, channel estimates, or noise estimates relative to the old receiver. This is a declared AWGN component fixture, not baseline detector qualification.
- Proposed permanent test bodies, mechanically renamed to call standalone candidate classes: both passed, exit 0. Coding test exercised 10 failed code blocks across its corrupted cases. The waveform test retained detection in both cases and rejected the wrong-RNTI CRC.
- pending_uci_crc_native_authority.patch: five files, including testAll registration; git apply --check passed against the base revision. It has NOT been applied.

The proposed production files and permanent tests are in uci_crc_integration_stage. This folder must NOT be added to the MATLAB path of an existing full-suite run. Portable test copies only call the separately named candidate classes.

All three existing full-suite runs were left running at the user's explicit direction. Their checkouts remain unchanged. They do not validate this candidate. After integration, run testAll and the repository/skill-required NR, strict-mode, grant, E2E, and export checks on the final source revision. No full-suite or 12 dB pass is claimed here.

Still separate and open: shared combined HARQ/CSI/SR PUCCH and PUSCH integration, baseline false/missed ACK qualification, CSI calendar and receiver-completion causality, DL fixture timing/CFO/EVM investigation, and integrated measurement/power/noise/loss/export closure.

Native API contract: https://www.mathworks.com/help/5g/ref/nrucidecode.html (second output reports actual decoding errors).
