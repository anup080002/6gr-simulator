# Requested 6G capability: 7 GHz, 400 MHz, TDD, DL/UL 1024-QAM

## Scope and status

User reprioritized on 17 September: stop bug repairs, finish the already
running 5 MHz / 12 dB diagnostic, then work on this new capability. Existing
unfinished mixed-feedback edits are preserved; they are not verified or
included in the frozen diagnostic. No existing acceptance assertion, noise
level, detector threshold or transmit power is to be changed to obtain a pass.

The requested full link is **not implemented/qualified yet**. This is an
explicit 6G research experiment, not an assertion of standardized 6G behavior.
Retain the requested 7 GHz center frequency; do not substitute 28/30 GHz or
mislabel the carrier as FR2/FR3 just to pass NR bandwidth validation. Retain
the requested SINR-sweep style operating point, not geometry-controlled noise.
Use the established configured reference-Es/N0 authority and separately export
measured reference/post-equalization SINR. Initial requested operating point
from the preceding request is 30 dB; preserve the later sweep
[-30, -20, -10, 0, 10, 20, 30, 40] dB.

## Existing capability and verified source boundaries

- `+sixgr/+phy/+frame/CarrierGridConfig.m` already provides an explicit
  `custom` API with nonstandard provenance and occupied-bandwidth checks.
  Candidate geometry: 264 PRBs, 120 kHz SCS, 380.16 MHz occupied bandwidth
  inside a 400 MHz channel, with a 4096-point FFT at 491.52 Msamples/s.
  These are proposed experiment settings, not a normative 7 GHz NR profile.
- `+sixgr/+lls6g/+config/validateScenarioConfig.m` currently reaches the custom
  grid API only through the FR3 label. YAML-to-runtime research-carrier
  selection needs an explicit independent mode, not a false frequency label.
- `+sixgr/+phy/+ul/+pusch/PUSCHModulator.m` explicitly rejects 1024-QAM.
  `PUSCHMCSResolver.m` supports only the existing NR qam64/qam256/low-SE tables.
- `+sixgr/+phy/+ul/PUSCH_Tx.m` uses native PUSCH configuration, indices,
  UL-SCH encoding, TBS and modulation. Changing one modulation enumeration
  would not add an end-to-end coded research uplink.
- Existing DL paths and generic NR symbol functions include 1024-QAM support,
  but this does not qualify the requested wideband bidirectional scenario.

Official capability reference: [MathWorks nrPUSCHConfig](https://www.mathworks.com/help/5g/ref/nrpuschconfig.html)
lists up to 256-QAM; [nrSymbolModulate](https://www.mathworks.com/help/5g/ref/nrsymbolmodulate.html)
documents 1024-QAM since R2023a. MATLAB R2023b compatibility must be checked
on that server, not inferred from the local R2026a installation.

## Implementation boundaries and test order

1. YAML catalog/defaults: explicit custom-carrier and experimental-UL policy;
   scenario class `optional_research_experiment`; bandwidth/frequency/SCS/grid,
   modulation, coding-rate definition, reference-SNR sweep and output controls.
2. Validation and `buildInternalConfig`: carry custom grid provenance through
   the existing frame/grid path. Preserve standard NR rejection behavior.
3. Experimental UL: explicit Qm=10 coding/TBS/rate-matching, modulation and
   soft-demodulation ownership, resource accounting, layer mapping, DM-RS and
   optional UCI. Do not use a dummy 256-QAM configuration to export Qm=10 TBS,
   G, grant or decoder results. Keep standard PUSCH unchanged.
4. Components: exhaustive symbol mapping/demapping and normalization; coded
   TX/RX round trips; exact RE/G/TBS accounting; per-resource fading-channel
   estimates and EVM; independent DL/UL checks. No arbitrary power injection.
5. Short wideband DL and UL waveform runs, then the integrated TDD scenario.
   A successful run must actually transmit 1024-QAM in both directions; an
   adaptive downgrade is not acceptance of this requested capability.
6. Required configuration/PHY/integrity tests and final-source `testAll`,
   then R2023b execution and the requested sweep. Preserve failed-run logs.

Capability probes are under `logs/6g_7ghz_400mhz_1024qam_capability_20260917`.
They inspect APIs and the constellation only; they are not link-run evidence.

## Executed capability probe: 17 September, 09:30 IST

On source `f8dddfeddf594f5a39999c75e2d706df84cae2c7`, MATLAB
R2026a Update 4, the probe exited **0**. This is a capability inspection,
not a waveform-link acceptance test:

| Check | Observed result |
| --- | --- |
| Native PDSCH `1024QAM` configuration | Accepted |
| Native PUSCH `1024QAM` configuration | Rejected: `MATLAB:nrPUSCHConfig:Modulation:unrecognizedStringChoice` |
| Repository strict UL modulation `1024QAM` | Rejected: `sixgr:pusch:UnsupportedModulation` |
| Standard FR1, 400 MHz, 120 kHz grid | Rejected: `sixgr:phy:frame:UnsupportedBandwidthSCSCombination` |
| Explicit custom 7 GHz, 400 MHz, 120 kHz, 264-PRB grid | Accepted |
| All 1,024 constellation points, hard-decision round trip | Exact bit equality |
| Exhaustive constellation mean energy | 0.99999999999999956 |

Probe log SHA256:
`38020BD2F045FCDEE378189E2E8DD6AD4582375EECF62189474E3AD75C8AE6E8`.
The preserved text log is
`docs/lls/evidence_20260917/wideband_capability_probe/matlab.txt`.
No 400 MHz channel, coded UL transmission, 30 dB link or throughput result
was executed by this probe. R2023b remains unverified. The next implementation
boundary is the explicit YAML-to-runtime custom carrier and experimental
coded Qm=10 uplink described above; the strict NR rejection must remain.

## Keysight IQ deliverable

Reuse `run_control.continuous_raw_iq_capture_enable` and the existing sealed
shared-clock capture. Preserve both DL and UL physical antenna streams after
waveform composition/TX RF and before propagation, including intentional TDD
silence and original sample indices. Keep the original floating-point samples.
The existing `sixgr.truth.exportContinuousKeysightPlaybackPackage` can create
headerless I/Q CSV, little-endian interleaved signed-int16 WIQ, and per-port
89600 VSA MAT (`Y`, `XDelta`, `InputCenter`, `InputZoom`, `XDomain`) in a separate
output directory. Reuse it rather than reconstructing IQ from constellation
points or repeating one slot.

Acceptance must retain sample rate, 7 GHz center frequency, source and output
SHA256 values, port synchronization, sample extent, common per-transmitter
playback scale and quantization-error/clipping checks. Playback normalization
is a documented file-format conversion, not additional simulated TX power or
a change to the captured floating-point reference. Actual Keysight software
import/demodulation remains separate from file-generation verification.

These are transmitter-output samples, captured before the channel. They do
not contain receiver noise or embed the requested 30 dB received operating
point. Any received-IQ delivery must use a separately identified receiver
capture; do not label pre-channel TX IQ as a 30 dB received waveform.

The latest requested first operating point is explicitly **30 dB**, with the
objective of high bidirectional throughput. Compare useful successfully
decoded TB bits over both the full TDD wall-clock interval and each direction's
active allocation time; do not present the latter as full-run goodput. Keep
retransmissions, control/pilot/guard overhead, configured rank, achieved rank,
MCS/code rate, BER/BLER and actual modulation visible. A 1024-QAM label alone
does not guarantee best throughput or an error-free result at 30 dB.
