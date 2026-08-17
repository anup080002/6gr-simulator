# LLS CSV-to-PNG artifact pipeline

This pipeline treats completed same-chain runtime CSV files as the only
scientific authority for regenerated charts. Repository `artifacts/` packs
define presentation and coverage expectations; their values and images are
never copied into a run as measurements.

The MATLAB `runtime_in_path` artifact catalog is deliberately CSV-only.
MATLAB does not register or render PRACH/PDSCH/PUSCH runtime PNGs. Any older
artifact-generation audit containing a PNG row is rejected during recovery
instead of recreating that legacy image. The post-run CSV contract
materializer is the sole raster producer.

## Ordered gates

1. Verify the exact `results/lls/<scenario>/<run>` identity and authority
   files.
2. Parse every CSV and publish per-file, per-column and population audits.
3. Pass the canonical PHY semantic gate: identity, trial uniqueness,
   configured/scheduled/transmitted/effective operating points, TBS/CRC/BER,
   throughput duration, noise/SINR/EVM lineage, MU receiver execution and
   truth/proxy lifecycle. When DL or UL trials exist, the gate also requires
   the nonempty, identity-bound `runtime_call_ledger.csv` with the actual
   canonical PDSCH/PUSCH Tx and Rx entry points. Trial rows are never used to
   reconstruct a missing call ledger.
4. Inventory every run-local PNG/JPEG by path, dimensions and SHA-256.
5. Delete only those inventoried run-local rasters.
6. Build eligible charts from exact CSV columns. Every chart records its
   source CSV hash, source rows, axis labels/units, mapping status and output
   PNG hash.
7. Suppress trend/curve claims with missing measurements, non-finite axes or
   too few independent samples. A bounded measured operating point may be
   shown only when it is explicitly labeled as an operating point rather
   than a sweep or fitted curve. Do not create an “unavailable” reason-card
   image.
8. Publish component views as byte-identical mirrors of canonical charts.
   Header-only CSV registries remain canonical-only and are not duplicated
   into component folders.
9. Re-synchronize every already-declared component CSV/image mirror after
   finalization updates its canonical lineage or status authority. Missing
   canonical authorities and path traversal fail closed.
10. Re-run CSV, chart-lineage, raster-decode and manifest audits.

## Scientific chart rules

- BLER/BER/FER curves require multiple independently executed SNR/SINR
  operating points and observed error/trial counts. A one-point diagnostic
  is not presented as a waterfall; scalar reliability charts report exact
  numerators/denominators and Wilson bounds.
- CDFs require enough genuine samples for a distribution; configured values
  are not repeated to manufacture samples.
- Resource-grid and occupancy images use persisted slot/symbol/PRB/RE rows.
- Constellation, EVM and per-layer plots use persisted receiver symbols and
  receiver measurements from the same Tx/channel/Rx execution.
- PRACH, SSB/PBCH, PDCCH, PUCCH, SRS, CSI-RS and TRS plots use their in-path
  control-trial tables and never a separately launched anchor.
- MU-MIMO plots distinguish DL joint per-RE MMSE-IRC equalization from an UL
  receive-combiner matrix; configured intent is not an applied algorithm.
- PNG is the publication raster format. SVG files are not persisted.

## Command

```powershell
python scripts/regenerate_lls_rasters_from_csv.py `
  --run-folder results/lls/<scenario>/<run> `
  --audit-output artifacts/focused_audits/<audit-name> `
  --execute
```

The command is fail-closed. It will not delete an image unless the primary
CSV semantic gate passes, and it refuses paths outside one exact LLS run.
On resumed finalization the MATLAB runtime ledger is preserved and appended;
an absent, header-only, identity-mismatched, proxy-labelled or corrupt ledger
blocks raster replacement.
