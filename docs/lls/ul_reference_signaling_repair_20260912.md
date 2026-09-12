# UL reference signaling: SRI and DM-RS field closure

Scope: the configured two-port, rank-one, CP-OFDM 12 dB baseline and focused
shared-clock regression. This is not whole-DCI, whole-NR or 400 MHz qualification.

## Verified defects and repairs

1. DCI 0_1 inherited a four-bit SRS resource indicator despite the runtime
   constructing exactly one codebook SRS resource. The corrected schema uses
   `ceil(log2(N_SRS))` bits; for one resource the field is absent. The receiver
   records an implicit index zero with its source, not fictitious received bits.
   Out-of-range resource indications fail. Multiple-resource serialization is
   tested independently; the current single-resource runtime explicitly rejects
   attempts to claim a larger executed resource set.
2. UL antenna-port indication used `rank-1`, with an inherited five-bit width.
   Rank alone does not identify DM-RS ports or CDM groups without data. The new
   ordinary type-1/maxLength-1 mapping uses three bits and TS 38.212 tables
   7.3.1.1.2-8/-9/-10/-11. For rank one, port zero and two CDM groups, the
   correct indication is codepoint two (`010`), not zero (`000`).
3. The scheduler now resolves the same PUSCH allocation and scheduled port set
   used by PHY construction, and encodes its actual DM-RS configuration. The
   receiver decodes ports, CDM group count and front-loaded symbol count. The
   shared-clock test compares these received fields against `p.Tx.PUSCH.DMRS`
   from the transmitter that produced the captured samples.

Source: [TS 38.212 V18.8.0, section 7.3.1.1.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf).

## Configuration authority

Both the continuous-IQ baseline and two-port shared fixture explicitly carry:

```yaml
reference_signals:
  pusch_dmrs_num_cdm_groups_without_data: 2
  pusch_dmrs_config_type: 1
  pusch_dmrs_max_length: 1
control:
  ul_reference_signaling:
    srs_resource_count: 1
    dmrs_configuration_type: 1
    dmrs_max_length: 1
    dmrs_type_enhanced: false
    multipanel_sdm: false
```

The catalog registers both new surfaces. CDM group count is mapped to the
runtime PUSCH configuration, not just exported from YAML. Unsupported enhanced,
double-symbol, transform-precoded or multi-panel combinations are rejected by
this table implementation, not silently mapped to a simpler configuration.
Those broader capabilities remain within the overall project goal.

## Verification

- `testULReferenceSignaling`: independent standard rows, SRI counts 1..4,
  absent-field semantics, exact emitted `010` bits, invalid/reserved rejection.
  Passed after correcting the new test's zero-based FieldTable indexing.
- `testTwoPortULYAMLAndSRS`: configured two-port sounding and DCI context. Passed.
- Configuration/catalog/scheduler checks: `test6GParameterCatalog`,
  `test6GScenarioConfigValidation`, `testSchedulerGrantConsistency`, `testConfig`.
  All four passed.
- DCI schema, pack/parse, sizing, wrong-context rejection and decoded-grant
  authority: five existing focused regressions passed.
- Updated shared-clock SRS → DCI → PUSCH/UCI test: PASS, including comparison
  against the actual transmitter DM-RS configuration. PUSCH CRC/UCI passed;
  received timing offset was 90 samples and residual timing error was zero.
- Early YAML authority validation rejects unexecuted multiple-resource SRS
  declarations, contradictory DM-RS settings and missing CDM-group authority.
  Final regression receipt records the outcomes; no runtime verdict is inferred
  from YAML alone.

No `testAll`, E2E campaign or full 58-slot baseline was launched in this pass.
Receipts are preserved under `docs/lls/evidence_20260912/` when terminal.

## Remaining mandatory control-path work

The next full run is still held. `DCIContextFactory.fromScheduledGrant` starts
from legacy context defaults when a complete operator context is absent;
overriding the corrected UL fields does not qualify all remaining fields.
The main `completePDCCHReception` supplies `K=numel(tx.DCIBits)` and the receiver
only searches candidate locations at that supplied length. Expected bits are
used after decoding for match evidence, but the payload-length authority still
comes from the transmitted grant rather than an independently installed
receiver monitoring context.

Next: make the baseline's complete control context YAML-owned; qualify DL
DM-RS field width/mapping and other optional-field presence; derive monitored
payload sizes from that context on the receiver; test wrong-size/format and
blind-decoding cases; then perform the one final full 12 dB validation and
audit original runtime evidence. Keep the previously requested long impairment
runs, single-carrier 400 MHz at 7 GHz and higher-QAM extensions after this
baseline gate, without relabeling study features as NR conformance.
