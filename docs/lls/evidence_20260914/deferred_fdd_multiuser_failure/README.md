# Deferred FDD multi-user failure, 14 September 2026

Observed in the already-running main full suite on be983bf4, worker 10448.
test6GLLSMultiUserBeamforming generated a 12-slot, two-UE FDD fixture from
lls_mimo4x4_multiuser_beamformed_cdl_d_fdd_validation.yaml. At slot 1 it reached
DL scheduling without received UL timing authority; attachReceivedULTimingAuthority
rejected it with sixgr:l2:mac:MissingReceivedULTiming. No data rows existed.
The test disables PBCH/PRACH/PDCCH/SRS/TRS control gating; further FDD repair
analysis is explicitly deferred by the user's TDD-only instruction.

These are snapshots of failure evidence while the parent full suite was still
running/recovering artifacts. They are not a terminal full-suite summary and
must not be mistaken for a 12 dB TDD result. The original suite logs remain in
logs/testall_20260914T035615537Z_ef864a72/. No process or evidence was removed.
