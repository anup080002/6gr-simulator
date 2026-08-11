# ISAC joint simulation implementation plan

## Objective

Implement one configuration-driven, time-domain ISAC campaign for RAN1 AI
10.8.2 and 10.8.3. The communication and sensing branches share the same
OFDM grid, transmitted samples, channel/target realization, event state,
collision mask, and received samples. No equation-only row is admitted to a
waveform-truth table.

## Production architecture

1. **Configuration/catalogs** — one master YAML contains execution mode,
   carrier, W0-W3 waveform profiles, sequence/reset rules, TDD patterns,
   sensing RE maps, collision responses, event models, coherency budgets,
   receiver profiles, geometry, targets, beam management, fairness and output
   contracts. Validation rejects missing or incompatible values.
2. **Grid and waveform builder** — constructs a physical NR CP-OFDM
   comparison grid, maps uncoded QPSK communication data and configured
   sensing REs, applies W0-W3
   frequency-domain phase/sequence rules, performs ordinary OFDM modulation,
   and records absolute symbol/subcarrier indices plus CP state.
3. **Integration state** — derives configured/collision/response/transmit/
   receive/effective masks and coherent segments. Puncturing never compresses
   the W3 absolute-symbol state.
4. **Channel and target adapter** — operates on the shared transmit samples.
   The controlled paired W0-W3 experiment executes explicit direct/target
   sample paths. The separate production PDSCH anchor executes
   `phased.ScatteringMIMOChannel`; the official `h38901ISACChannel` helper is
   supplementary reference evidence. Geometry-derived delay and bistatic
   Doppler are always exported independently for validation.
5. **Receiver/measurements** — communication demodulation and sensing
   correlation consume the same receive observation. The receiver exports
   range-Doppler/angle estimates, ambiguity state, PD/PFA decisions, error,
   uncoded communication EVM/SER/goodput, and complexity. Coded PDSCH CRC,
   bit errors and post-equalization metrics come only from the production
   full-PHY anchor and are never inferred from the component experiment.
6. **Coherency-budget selector** — evaluates all configured actions against
   requested measurement and residual phase/timing/frequency limits, stores
   feasibility for every action, and applies the declared fallback order.
7. **Reporting** — writes raw and aggregate MAT/CSV data first. All PNGs are
   regenerated from those saved tables/configuration and bound by SHA-256
   lineage. SVG output is prohibited in accordance with the repository raster
   policy and the user's output requirement.

## Execution modes

- `quick`: deterministic minimal coverage of every module, analytical/unit
  tests, one monostatic and one bistatic waveform trial, and complete file
  contract. Evidence class `engineering_regression`.
- `tdoc`: staged J1-J4 reduced matrix, paired seeds, per-trial evidence and
  confidence intervals. Produces all 57 named PNGs and 17 table groups.
- `full`: YAML-owned production trial counts and the complete staged matrix;
  never silently selected by a quick run.

## Implementation sequence and gates

1. Source availability audit and this plan/source map.
2. Add strict config loader/validator and the two carrier profiles.
3. Implement W0-W3 grid builder and absolute-index cumulative-CP state.
4. Implement effective-pattern/event/TDD/collision state and budget selector.
5. Implement geometry, analytical bistatic Doppler, channel adapter, common
   observation, receiver, and communication/sensing metrics.
6. Implement beam-management and assistance experiments without ML.
7. Implement raw/aggregate serialization, deterministic hashing, 57 named
   raster figures, 17 tables, manifest, report and regeneration command.
8. Add the 14 mandatory analytical/unit checks plus provenance/fail-closed
   tests.
9. Run focused quick tests, repair failures, then run the quick campaign.
10. Audit every emitted CSV column, image dimensions/hash/lineage and manifest.
11. Run the reduced TDoc matrix only after quick gates pass; regenerate figures
    from saved results and verify deterministic hashes.

## Truth and qualification rules

- `waveform_truth` requires executed waveform samples and receive samples.
- Analytical references are stored in `analytical_reference` tables and may
  validate truth; they cannot replace it.
- Configured target values are truth geometry, never measured estimates.
- Simulation and NI-USRP hardware evidence are distinct execution backends.
- A probability is not publication-qualified unless its configured trial count
  supports the requested confidence interval; otherwise the row is explicitly
  `insufficient_trials`.
- Missing outputs fail the contract; the reporter does not create placeholder
  success rows or duplicate a value just to fill a figure.

## Initial reduced TDoc wave

The first bounded TDoc run covers both FR3 and FR2 carrier validation, executes
FR3 waveform truth for W0-W3 below/at/above CP, one monostatic and one TRP-TRP
bistatic geometry, two TDD patterns, collision-free/puncture/relocate actions,
range-only and range+Doppler coherency decisions, one- and eight-port metadata,
and deterministic beam-management sensitivity. The full YAML matrix remains
available for the subsequent complete campaign.
