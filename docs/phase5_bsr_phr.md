# Phase 5 BSR And PHR

Status: BSR/PHR helpers exist; connected decoded-PDU ownership pending.

`+sixgr/+l2/+mac/BSR_PHR.m` can build and decode Short BSR, Long BSR and Single
Entry PHR payloads. Phase 5 requires those payloads to be carried in actual
decoded MAC PDUs before the gNB scheduler updates UL buffer or power-headroom
state.

Forbidden Phase 5 shortcut:

- Do not set scheduler `ULBufferBytes` from the UE queue object.
- Do not fabricate BSR activity because the UE has traffic.
- Do not mark PHR present unless it was encoded and decoded in a MAC PDU, or
  explicitly disabled by configuration.
