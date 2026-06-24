# Phase 5 PUCCH Format 0

Status: waveform evidence exists; connected policy evidence pending.

`+sixgr/+phy/+ul/PUCCH_Tx.m` and `+sixgr/+phy/+ul/PUCCH_Rx.m` support PUCCH
Format 0 through 5G Toolbox primitives. Format 0 maps short UCI directly and
does not carry a transport-block-style CRC.

Required fields for Phase 5 runtime rows:

- detection status
- UCI hypothesis
- hypothesis or detection metric
- DTX decision
- decoded bits
- confidence or metric status
- false-alarm status where calibrated

Do not convert DTX or missed detection into NACK unless the configured policy
explicitly requires that interpretation and records the distinction.
