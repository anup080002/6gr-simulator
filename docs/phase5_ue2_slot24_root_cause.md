# Phase 5 UE2 Slot 24 Root Cause

Status: pending live reproduction.

Known prior symptom:

- UE: 2
- Direction: DL
- Slot: 24
- MCS: 18
- Modulation: 64QAM
- Decoder iterations: 100
- Raw BER: approximately 0.140
- TB CRC: fail

The diagnostic scaffold lives under `debug/ue2_slot24/`. It intentionally
contains pending schemas rather than invented data. The next runtime patch must
capture the exact grant, DCI bits, decoded fields, resource mapping, channel/RF
state, timing/CFO/noise/equalizer state, LLRs, rate-recovered LLRs, decoder
state, code-block CRCs, TB CRC and Tx/Rx hashes.

Do not hide this failure by lowering global MCS, disabling the grant, skipping
UE2, forcing ACK, changing the seed, replacing the channel, increasing decoder
iterations without diagnosis, or using an ideal receiver as production.
