# Phase 5 PUCCH Format 1

Status: waveform evidence exists; connected policy evidence pending.

Format 1 adds DM-RS-backed reception and can carry HARQ-ACK/SR payloads without
a transport-block-style CRC. Existing strict control-channel tests check that
PUCCH CRC fields are populated only when the format and payload make them
applicable.

Phase 5 must prove:

- UE-specific PUCCH resource selection from decoded configuration.
- HARQ-ACK and SR bit mapping.
- DM-RS resource and channel-estimation evidence.
- DTX, NACK and ACK are distinct runtime outcomes.
- PUCCH feedback updates HARQ only after gNB waveform decode.
