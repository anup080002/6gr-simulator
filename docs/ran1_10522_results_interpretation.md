# RAN1 AI 10.5.2.2 results interpretation

`ANALYTICAL_DERIVATION` rows are exact for the configured equations, but are not receiver performance measurements. `CONCEPTUAL_DIAGRAM` PNGs are replayed from those source CSVs. `CONTROLLED_LLS` rows come from the canonical PDSCH waveform/receiver/CRC chain and retain execution backend, approximation mode, channel, seed and confidence fields.

The short run is an integration qualification, not a decision-quality curve. BLER zero from one block has a wide Wilson interval and cannot establish required SNR. `point_status.csv`, `proposal_evidence_matrix.csv` and `limitations.csv` are the authority for claim eligibility. No artifact is copied to `tdoc_ready` while any required proposal remains unsupported.

Raster figures are PNG-only according to the current user output requirement. The figure manifest binds every image to its source CSV and SHA-256; replay must reproduce identical PNG hashes.
