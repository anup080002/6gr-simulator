"""Render isolated candidate previews, without claiming integrated run provenance."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys

candidate = Path(__file__).resolve().parent
repo = Path(sys.argv[1]).resolve()
sys.path[:0] = [str(candidate / "apps"), str(repo / "apps")]
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio

source = repo / "docs/lls/evidence_20260913/projected_ul_late_uci_capture_01/air_interface/csv/ul_pusch_trials.csv"
destination = Path(sys.argv[2]).resolve()
if destination.exists():
    raise SystemExit("Use a new output folder; existing evidence is preserved.")
payload = source.read_bytes()
outputs = {}
for name, slug in [("throughput vs SINR", "throughput_vs_sinr"),
                   ("PUSCH BLER vs measured SINR", "pusch_bler_vs_measured_sinr")]:
    result = m._specialized_chart_materialization(name,
        {"air_interface/csv/ul_pusch_trials.csv": {"artifact_id": 1}}, lambda _: payload, "candidate_preview")
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    key = "sinr_is_limited" if slug == "throughput_vs_sinr" else "x_is_limited"
    assert len(rows) == 1 and rows[0][key] == "True"
    assert b"Limited values are not raw estimates" in result["img_bytes"]
    outputs[slug + ".csv"] = result["csv_bytes"]
    outputs[slug + ".png"] = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
receipt = {"scope": "isolated_python_candidate_replot_of_retained_component_evidence",
           "integrated_into_runtime": False, "full_run_qualification": False,
           "source_path": str(source), "source_sha256": hashlib.sha256(payload).hexdigest(),
           "producer_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in [Path(m.__file__), Path(radio.__file__), Path(__file__)]},
           "artifact_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in outputs.items()}}
destination.mkdir(parents=True)
for name, data in outputs.items():
    (destination / name).write_bytes(data)
(destination / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps(receipt, indent=2))
