# Phase 5 HARQ-ACK Codebook

Status: pending connected-mode codebook evidence.

The current runtime can schedule PUCCH feedback due slots and write PUCCH grant
trace rows, but Phase 5 still needs a connected-mode HARQ-ACK codebook audit.

Required checks:

- One and multiple PDSCH feedback cases.
- DAI and bit ordering where configured.
- Missing PDSCH and DTX handling.
- Feedback timing legality under the TDD pattern.
- No direct UE CRC update of gNB DL HARQ state.

The codebook output must feed PUCCH UCI bits, then gNB HARQ state must consume
only decoded PUCCH observations.
