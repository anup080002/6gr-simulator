# Shared PUSCH development evidence, 2026-09-14

These are unchanged terminal reports copied from two clean-source focused
runs. Neither run is testAll or integrated 12 dB qualification.

- c4ce36c3: five passes (independent periodic CSI receive obligation, UCI
  codec/normalization, received UL DAI producer/gap bindings, actual staged
  TDD and FDD receiver handoff). All eight staged cases retained actual samples.
- 8a007054: five passes (separate UE/gNB producer positions, receipt guard,
  reservation preflight, preflight reducer, independent UCI codec).
  Mapping/receipt cases are declared contracts, not physical HARQ commits.

The new common-completion adapter has not been qualified through the normal
coordinator. Independent mixed-resource ownership, missed UL DCI receive-only
handling, final-source regression, PUCCH qualification and integrated output
audits remain open. Do not merge this evidence into primary measurement rows.

Large staged MAT captures and the first run's logs were copied, without
removing their originals, into the main checkout under
logs/shared_pusch_receiver_checkpoint_20260914_c4ce36c3/ (505,566,891 capture
bytes across eight folders). Full run paths and MATLAB/source identities are
in launcher.json. These captures are local logs, not included in these small
Git-tracked receipts. Failed historical runs remain preserved separately.
