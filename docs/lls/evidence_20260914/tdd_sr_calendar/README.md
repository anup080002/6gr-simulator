# TDD SR calendar candidate and retained archive review

14 September 2026. This evidence does not qualify the integrated 12 dB run.

The JSON audit is a historical snapshot against 35ec47cb and 03f6d6c7;
its SR-schema-pending flag describes the state before this candidate patch.
All eight remaining ambiguous archives are reconciled, not blindly reapplied.
Their original archives, failed runs and logs remain preserved.

The current SR patch installs explicit configuration/schema/calendar support
and uses the calendar in the independent HARQ-only PUCCH receive hypothesis.
Unsupported SR overlap still fails closed. MAC lifecycle, general mixed UCI
and signal-present SR reception remain unqualified. The production 12 dB
configuration and all PHY numerical gates are unchanged.

The slot-period/capability catalog follows SchedulingRequestResourceConfig in
[TS 38.331 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.08.00_60/ts_138331v180800p.pdf), page 1064.
Format 2/3/4 overlap-count algebra follows section 9.2.5.1 of
[TS 38.213 V18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
Neither reference is a simulator conformance certificate.

Pre-runtime checks: native mlint found no SYNER/EOLPAR in the seven changed
MATLAB files; an intentionally malformed file produced SYNER. Schema JSON
parse and git diff --check passed. Runtime results must be read separately
from the revision-specific logs/testall_* receipt, never inferred from this
static checkpoint. No new FDD-focused run is included.
