# DL DM-RS indication and scheduled-port precedence repair

Scope: the active continuous-IQ baseline's ordinary type-1, maxLength-1,
single-codeword DL signaling. This closes specific signaling defects, not
whole-DCI, whole-NR, full-run or publication qualification.

## Root causes and implemented changes

- The scheduler and standalone DCI 1_1 builder encoded `NumLayers-1` as the
  antenna-port indication. This is not a DM-RS table lookup: for two layers,
  ports `[0,1]` and one CDM group, the indication must be 2, not 1. Likewise,
  rank-one port zero with two CDM groups requires indication 3, not zero.
- The schema inherited five antenna-port bits. The configured ordinary
  type-1/maxLength-1 table requires four. `DLReferenceSignaling` now encodes
  all twelve valid rows, decodes the ordered port set, CDM group count and
  rank, and rejects reserved values 12..15. Port values are logical indices;
  the corresponding PDSCH DM-RS antenna port is 1000 plus that index.
- The scheduler constructs the actual PDSCH configuration using the shared
  configuration factory before encoding its DM-RS selection. Transmitter
  assignment binding checks the serialized ports and rank against the
  scheduled PDSCH instead of trusting that a rank-only field means the same
  thing. This check parses authored bits; it does not claim reception.
- The earlier UL helper wrote `dmrs.portSet`, which has lower priority than
  `dmrs.availablePortSet`. An explicitly scheduled nonzero port could thus
  be replaced by the first pool port when forming its DCI indication. Both
  helpers now supply `dmrs.scheduledPortSet`. A test with scheduled UL port
  one verifies indication 3 for two CDM groups, independently of pool zero.

Source: [TS 38.212 V18.8.0, section 7.3.1.2.2 and table 7.3.1.2.2-1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf).

## YAML authority

The continuous-IQ baseline now declares `reference_signals.pdsch_dmrs_max_length: 1`
and this catalog-registered control context:

```yaml
control:
  dl_reference_signaling:
    dmrs_configuration_type: 1
    dmrs_max_length: 1
    dmrs_type_enhanced: false
    two_tci_states: false
    max_codewords: 1
```

Validation rejects missing or contradictory DM-RS authority. Enhanced DM-RS,
two-TCI-state mappings, other DM-RS types/lengths and two-codeword signaling
are not implemented by this table helper and fail explicitly. Existing
unconfigured compatibility callers are not upgraded to a qualified standard
context by this change.

## Verification and limits

`testDLReferenceSignaling` and `testULReferenceSignaling` passed. The new test
checks twelve independently specified table rows, exact emitted four-bit
indications, reserved values, port order, YAML contradictions, scheduled-port
precedence, and actual PDCCH reception matching the coded PDSCH transmitter's
DM-RS configuration. Its PDCCH waveform check uses a unit channel and an
explicit known payload size; it is not independent blind-size qualification
or a full 12 dB performance result.

The first new fixture attempt was correctly rejected for SS/PBCH/DM-RS
collision in slot zero. The fixture was moved to the baseline's DL data
occasion at one-based slot 31. The collision guard was not weakened, and
the original failed log is retained.

All ten related regressions passed: config, scenario catalog/validation,
scheduler grants, DCI 0_1 schema, pack/parse, size alignment, wrong-context
rejection, decoded grant authority and two-port SRS/TPMI. The receipt and logs
are under `evidence_20260912/lls_dl_reference_*`. These existing tests include
compatibility contexts and therefore do not qualify every configured DCI bit.

No full 58-slot run, `testAll`, E2E campaign, historical result reconstruction
or SINR adjustment was performed.

## Mandatory work before the next full baseline

1. Replace inherited legacy DCI policy with a complete configuration-owned
   connected control context. The current factory still starts from legacy
   defaults when no complete operator context is installed.
2. Correct optional field presence and widths against the configured RRC
   features. Inspection identifies unconditional VRB mapping, PRB bundling,
   legacy rate-match/ZP-CSI-RS/CBG fields and a CSI-request field in DCI 1_1.
   Also verify zero-bit single-entry TDRA, HARQ field sizes, K1 list indexing,
   UL DM-RS sequence initialization and PTRS/CBG field independence.
3. Use the receiver-owned monitored contexts to obtain payload sizes and
   formats. `completePDCCHReception` still gets K from `numel(tx.DCIBits)`.
   `PDCCHReceiver.prepare/receive` already contains a configuration-based
   multi-context search; integrate it or reuse its verified semantics without
   introducing transmitter payload/format authority under another name.
4. Carry actual decoded reference selections into the shared receiver
   assignment and exported control evidence. The current main grant binding
   hashes a subset of allocation/HARQ fields; it does not by itself prove
   all reference-signaling fields were materialized at the receiver.
5. Run focused positive/negative and shared-waveform tests for those repairs,
   then one fresh 58-slot 12 dB run and audit its original CSV/PNG/IQ/terminal
   evidence. Previous run artifacts cannot prove new runtime fields.

The remaining production qualification, long impairment runs, single-carrier
400 MHz/7 GHz experiment, higher-QAM integration and hardware playback remain
in the overall issue ledger; none is redefined as completed by this repair.
