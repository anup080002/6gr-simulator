# CSI PUCCH resource-authority checkpoint

Source: 051849374b0edb2b2da14cea93dc1d7520ef6a5a, clean and unchanged
through the run. Seven focused tests passed; MATLAB and launcher exit codes
were zero. The terminal launcher finished 2026-09-14 05:07:17 UTC.

Coverage: configured CSI resource outside HARQ sets, calendar/transmit identity,
PRI independence, unavailable PRI/TBS trace semantics, invalid bindings,
resource planning without power, nine PRB/numerology power vectors, multi-user
HARQ DCI PRI, FDD/TDD SRS collisions, periodic calendar and actual shared TDD
CSI reception with decoded delivery and power-export CSV roundtrip.

Not covered by this receipt: the newly added FDD/combined/stale-metadata
wrapper, general mixed-UCI ownership, normal independent PUSCH coordinator
integration, final-source testAll, detector qualification or integrated 12 dB.
The actual CSI reception test uses declared component inputs; it does not
qualify initial access or actual CSI measurement generation.

Original local run: logs/testall_20260914T050256906Z_91f1726f in the
sixgr_type2_runtime_20260913 checkout. The three JSON files here are exact
portable terminal receipts, not substitute RF captures or a conformance claim.
