# ISAC joint simulation source map

Generated for the SixGR RAN1 AI 10.8.2 and 10.8.3 implementation. This
document records the authority of every implemented assumption. Missing
source material is a visible limitation, never an invitation to invent a
value.

## Source availability audit

The repository, Downloads, Desktop, Documents, OneDrive, and Codex attachment
directories were searched recursively on 2026-08-12. None of the following
mandatory DOCX sources named by the master prompt was present:

1. `R1-26xxxx_Jio_ISAC_Integration_Maastricht_Final_Submission.docx`
2. `R1-26xxxx_Jio_ISAC_Integration_Maastricht_Final.docx`
3. `Patent_Coherency_Budgeted_Collision_Handling_ISAC.docx`
4. `R1-2605133 Summary on ISAC integration_v055_ZTE_Moderator.docx`
5. `R1-26xxxx_Discussion_on_CP_OFDM_multi_symbol_sensing_RS_corrected.docx`
6. `R1-26xxxx_Discussion_on_CP_OFDM_sensing_RS_frame_anchored_evaluation_6G_ISAC_final.docx`
7. `R1-2603665 Discussion on integration aspects for 6G ISAC.docx`
8. `R1-2603605 Discussion on aspects of integration of sensing with communication.docx`
9. `R1-2603537` / `R1-2503537 sensing integration 10_8_2.docx`

Their status is `required_source_unavailable`. No claim in this campaign is
attributed to one of these documents until the exact file is supplied and
hashed. The values below come either from the supplied master prompt, an
official MathWorks example, the existing SixGR configuration, or a clearly
labelled company-selected study setting.

## Governing sources

| Source | Version/access | Used for | Authority |
|---|---|---|---|
| `SixGR_Codex_Master_Prompt_10_8_2_10_8_3.md` | local file read 2026-08-12 | W0-W3 definitions, equations, event/TDD/collision/coherency sweeps, figure/table contract, tests, fairness | source-mandated campaign contract |
| MathWorks, *Introduction to TR 38.901 ISAC Channel Model* | R2026a online help | combined background/target channel, node/array geometry, supported sensing modes, moving target state, waveform filtering | external reference behavior |
| MathWorks, *Integrated Sensing and Communication Using 5G Waveform* | R2025a/R2026a online help | exact OFDM waveform reuse, DM-RS channel observations, TRP-UE bistatic geometry, range/angle processing | external reference behavior |
| MathWorks, *Integrated Sensing and Communication Using 6G Waveform on NI USRP Radio* | R2026a online help | optional pre-6G carrier/physical-channel/RS adapter and hardware interface boundary | external reference behavior; hardware validation is not claimed |
| existing `+sixgr/+lls/runISACSensingTrial.m` | repository commit at run time | exact committed PDSCH waveform capture, physical array projection, scattering channel, matched filtering/beamforming/CFAR | existing SixGR production default |

## Source-mandated equations and invariants

### Bistatic delay and Doppler

For transmitter position `pT`, receiver position `pR`, target position `p`,
target velocity `v`, propagation speed `c`, and wavelength `lambda`:

```text
tau_b = (||p-pT|| + ||p-pR||) / c
nu_b  = v^T (uT + uR) / lambda
uT    = (p-pT) / ||p-pT||
uR    = (p-pR) / ||p-pR||
```

The sign of the stored Doppler depends on the complex exponential convention
and is exported explicitly. In the monostatic special case the magnitude is
`2*radialSpeed/lambda`. A blanket factor of two is forbidden for bistatic
geometry.

### Frame-anchored cumulative-CP profile W3

For absolute OFDM symbol `l`, physical subcarrier index `k`, transform size
`N`, reset anchor `l0`, and the CP lengths of all symbols in the interval:

```text
q(l)   = mod(sum(CP(i), i=l0..l-1), N)
X_l(k) = A_h(m(k)) * exp(+j*2*pi*k*q(l)/N)
```

`q(l)` is advanced by absolute scheduled symbols, including symbols whose
sensing REs are later punctured. It is never advanced by a compressed count
of transmitted sensing symbols. The receiver independently reconstructs and
removes the phase from saved configuration/event state. IFFT and CP insertion
remain ordinary CP-OFDM.

### Phase-step coherent gain

For a fraction `a` before a common phase step `DeltaPhi`:

```text
G = |a + (1-a)*exp(j*DeltaPhi)|^2
```

### Effective sensing pattern

```text
S_eff = derive(S_cfg, collisionMask, collisionResponse, eventState)
```

The configured pattern, collision mask, response decision, transmitted
pattern, received pattern, and coherent-segment labels are stored separately.

## Source-mandated profiles and sweeps

- Carrier profiles: FR3 7 GHz, 100 MHz, 30 kHz SCS; FR2 30 GHz, 200 MHz,
  120 kHz SCS where supported.
- Waveforms: W0 communication-aligned CP-OFDM RS reuse; W1 randomized
  sequence; W2 repeated base sequence; W3 frame-anchored cumulative CP.
- Receiver baselines: B0 ordinary processing, B1 no-transmitter-change
  multi-symbol linear-convolution processing, B2 enhanced processing for W3,
  and C0 a declared comparison receiver.
- Delay/CP ratios: `[0.25,0.5,0.9,1,1.1,1.25,1.5,2,3]`.
- Symbols per coherent interval: `[1,2,4,8,14]`.
- normalized Doppler: `[0,0.01,0.05,0.1]`.
- TDD patterns: all-DL, `DDDSU`, `DDDSUDDSUU`, `DDDDDDDSUU`, `DSUUU`.
- Exact 40-slot TDD sensing set:
  `{0,2,6,7,10,11,16,17,20,22,25,27,30,32,35,37}`.
- collision ratios: `[0,5,10,20]` percent, with ten response classes retained
  in the response catalog.
- coherency budgets: maximum segments `[1,2,4]`, minimum segment lengths
  `[8,16,24,32]`, phase residual limits `[10,20,30,60,90]` degrees, and
  range / Doppler / angle measurement combinations.
- ports: 1 and 8-port half-wavelength ULA.
- beam-management study: 32-element ULA, 32 narrow beams over -60 to +60
  degrees, 8 wide beams, four narrow refinements, and the age/error settings
  stated in the master prompt.

## Company-selected implementation settings

The following are configurable YAML values rather than normative numbers:

- deterministic campaign seed and number of trials per mode;
- exact OFDM grid size compatible with the selected MATLAB carrier;
- CFAR guard/training cell counts and finite quick-mode false-alarm trial count;
- target geometry, RCS/complex reflection coefficient, and receive noise;
- output image resolution and raster format;
- reduced TDoc matrix selection used to make the first end-to-end run bounded.

Every selected value is serialized in the resolved configuration and run
manifest. Quick mode is labelled `engineering_regression`; it is not promoted
to publication statistics.

## Existing defaults retained or replaced

- Retained: exact runtime PDSCH waveform identity checks, physical antenna
  projection, deterministic seeds, measured receive cube hashing, matched
  filtering, array beamforming, CFAR, and PNG/CSV lineage.
- Replaced for the joint campaign: the previous single waveform/single event
  output is expanded into W0-W3, event, TDD, collision, coherency-budget,
  beam-management, joint-interaction, and fair-comparison tables.
- Optional: the R2026a `h38901ISACChannel` example backend is selected only
  when its example-local helper is installed on the MATLAB path. A requested
  but unavailable backend fails closed; it is not replaced with a scattering
  proxy.
- Optional hardware: NI-USRP execution has its own backend and evidence class.
  A simulation run never sets `HardwareValidated=true`.

## Unresolved source conflicts

No cross-DOCX conflict can be evaluated while the nine documents are absent.
The campaign stores candidate IDs and source status so exact document-derived
configurations can be added without rewriting production algorithms once the
files are supplied.
