# Phase 5 No-Oracle Policy

Status: policy scaffold and current boundary map.

See `phase5_baseline/current_oracle_fields.csv` for the current boundary
inventory.

Receiver forbidden inputs in Phase 5 include:

- transmitted TB bits
- expected CRC
- expected MCS, TBS, PRBs, symbols or ACK
- expected BSR or SR state
- selected PDCCH candidate
- ideal channel or true noise variance
- UE local queue state before SR/BSR decode

Allowed scheduler inputs include gNB queues, transmitted grants, configured UE
capabilities, decoded PUCCH, decoded SR, decoded BSR, decoded PHR, decoded
PUSCH and permitted HARQ state.

Reference modes are allowed only for post-run diagnosis. They must not be used
as production fixes or primary result rows.
