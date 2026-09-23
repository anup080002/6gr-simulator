"""Focused chart replay from retained PHY samples; never changes run acceptance."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def replay(run_folder: Path, output_folder: Path):
    source_path = "reports/csv/phy_signal_diagnostic_source.csv"
    source = run_folder.resolve() / source_path
    source_hash = sha256(source)
    panels = {"pre_equalization_re_cloud", "true_channel_impulse_response",
              "true_channel_frequency_response"}
    # Bounded exact-row extraction avoids loading unrelated heatmap tensors.
    # This is focused consumer verification, not a complete materializer run.
    with source.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        header = reader.fieldnames
        rows = [r for r in reader if r.get("Panel") in panels]
    payload = materializer._encode_dict_rows(header, rows)
    charts = ["pre-equalization constellation", "true H(tau) if available",
              "channel impulse response", "true H(f) if available", "tap power profile"]
    output_folder.mkdir(parents=True, exist_ok=False)
    records = []
    for index, name in enumerate(charts, 1):
        result = materializer._specialized_chart_materialization(
            name, {source_path: {"artifact_id": 1}}, lambda _: payload, 0)
        if result is None or result["source_mapping_status"] != "exact":
            raise RuntimeError(f"Missing exact captured evidence: {name}")
        png = materializer._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
        reason = materializer._png_low_information_reason(png)
        if reason:
            raise RuntimeError(f"Chart rejected: {name}: {reason}")
        prefix = f"{index:02d}"
        csv_path, png_path = output_folder / f"{prefix}.csv", output_folder / f"{prefix}.png"
        csv_path.write_bytes(result["csv_bytes"])
        png_path.write_bytes(png)
        records.append(dict(chart=name, rows=result["source_row_count"],
                            csv=csv_path.name, png=png_path.name,
                            csv_sha256=sha256(csv_path), png_sha256=sha256(png_path)))
        print(f"PASS {name}: {result['source_row_count']} exact rows", flush=True)
    if sha256(source) != source_hash:
        raise RuntimeError("Retained source changed during chart replay")
    receipt = dict(scope="focused_retained_chart_replay_not_scenario_acceptance",
                   source_run=str(run_folder.resolve()), source_table=source_path,
                   source_sha256=source_hash, extracted_panels=sorted(panels),
                   materializer_version=materializer.MATERIALIZER_VERSION,
                   materializer_sha256=sha256(Path(materializer.__file__)), charts=records)
    (output_folder / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(f"REPLAY_FOLDER={output_folder.resolve()}", flush=True)


def replay_constellation_layers(run_folder: Path, output_folder: Path):
    """Re-render exact retained layer samples, without updating run acceptance."""
    source_path = "reports/csv/equalized_constellations.csv"
    source = run_folder.resolve() / source_path
    source_hash = sha256(source)
    payload = source.read_bytes()
    result = materializer._specialized_chart_materialization(
        "constellation per layer", {source_path: {"artifact_id": 1}}, lambda _: payload, 0)
    if result is None:
        raise RuntimeError("No captured per-layer constellation evidence")
    _, rows = materializer._decode_csv_dicts(result["csv_bytes"])
    groups = sorted({(r["direction"], int(r["LayerIndex"])) for r in rows})
    root = ET.fromstring(result["img_bytes"])
    labels = {node.text for node in root.findall("{http://www.w3.org/2000/svg}text")}
    if not groups or any(f"{direction} LayerIndex {layer}" not in labels for direction, layer in groups):
        raise RuntimeError("A retained CSV layer is missing from the rendered image")
    png = materializer._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    reason = materializer._png_low_information_reason(png)
    if reason:
        raise RuntimeError(f"Layer chart rejected: {reason}")
    output_folder.mkdir(parents=True, exist_ok=False)
    artifacts = {}
    for suffix, data in (("csv", result["csv_bytes"]), ("svg", result["img_bytes"]), ("png", png)):
        path = output_folder / f"constellation_layers.{suffix}"
        path.write_bytes(data)
        artifacts[path.name] = sha256(path)
    if sha256(source) != source_hash:
        raise RuntimeError("Retained source changed during layer replay")
    receipt = dict(scope="retained_layer_chart_replay_not_scenario_acceptance",
                   source_run=str(run_folder.resolve()), source_table=source_path,
                   source_sha256=source_hash, rows=len(rows), layer_groups=groups,
                   materializer_version=materializer.MATERIALIZER_VERSION,
                   materializer_sha256=sha256(Path(materializer.__file__)), artifacts=artifacts)
    (output_folder / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(f"LAYER_REPLAY_PASS rows={len(rows)} groups={groups} output={output_folder.resolve()}", flush=True)


def replay_sinr_timeline(run_folder: Path, output_folder: Path):
    import lls_radio_measurement_plots as radio
    sources = [run_folder.resolve() / name for name in radio.TRIALS]
    sources = [path for path in sources if path.is_file()]
    hashes = {str(path): sha256(path) for path in sources}
    payloads = {index: path.read_bytes() for index, path in enumerate(sources, 1)}
    existing = {path.relative_to(run_folder.resolve()).as_posix(): {"artifact_id": index}
                for index, path in enumerate(sources, 1)}
    result = materializer._specialized_chart_materialization(
        "measured_sinr_vs_slot", existing, payloads.__getitem__, 0)
    if result is None or result["csv_status"] == "unavailable_exact_reason":
        raise RuntimeError("No eligible retained receiver SINR timeline")
    _, rows = materializer._decode_csv_dicts(result["csv_bytes"])
    input_rows = sum(len(materializer._decode_csv_dicts(data)[1]) for data in payloads.values())
    if len(rows) != input_rows:
        raise RuntimeError("Timeline lost retained receiver observations")
    png = materializer._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    if materializer._png_low_information_reason(png):
        raise RuntimeError("Receiver timeline raster failed information validation")
    if any(sha256(Path(path)) != digest for path, digest in hashes.items()):
        raise RuntimeError("Retained receiver source changed during replay")
    output_folder.mkdir(parents=True, exist_ok=False)
    for suffix, data in (("csv", result["csv_bytes"]), ("svg", result["img_bytes"]), ("png", png)):
        (output_folder / f"measured_sinr_vs_slot.{suffix}").write_bytes(data)
    receipt = dict(scope="retained_receiver_timeline_replay_not_scenario_acceptance",
                   source_sha256=hashes, row_count=len(rows),
                   available_rows=sum(row["value_status"] == "available" for row in rows),
                   directions=sorted({row["direction"] for row in rows}),
                   materializer_version=materializer.MATERIALIZER_VERSION,
                   materializer_sha256=sha256(Path(materializer.__file__)),
                   radio_plotter_sha256=sha256(Path(radio.__file__)))
    (output_folder / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    print(f"REPLAY_FOLDER={output_folder.resolve()}")


def replay_reliability(run_folder: Path, output_folder: Path):
    """Replay recorded CRC observations, preserving the original acceptance."""
    names = ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"]
    payloads = {index: (run_folder.resolve() / name).read_bytes()
                for index, name in enumerate(names)}
    hashes = {name: hashlib.sha256(payloads[index]).hexdigest()
              for index, name in enumerate(names)}
    existing = {name: dict(artifact_id=index, logical_path=name)
                for index, name in enumerate(names)}
    output_folder.mkdir(parents=True, exist_ok=False)
    records = []
    for index, name in enumerate(["BLER vs SNR", "BLER vs SINR"], 1):
        result = materializer._specialized_chart_materialization(
            name, existing, payloads.__getitem__, 0)
        if result is None or result["source_row_count"] == 0:
            raise RuntimeError(f"No observed reliability data: {name}")
        png = materializer._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
        if materializer._png_low_information_reason(png):
            raise RuntimeError(f"Reliability chart failed raster validation: {name}")
        artifacts = {}
        for extension, data in (("csv", result["csv_bytes"]), ("svg", result["img_bytes"]), ("png", png)):
            path = output_folder / f"{index:02d}_reliability.{extension}"
            path.write_bytes(data)
            artifacts[path.name] = sha256(path)
        records.append(dict(chart=name, source_rows=result["source_row_count"],
                            sources=result["source_table_path"], artifacts=artifacts))
    if any(sha256(run_folder.resolve() / name) != digest for name, digest in hashes.items()):
        raise RuntimeError("Retained reliability source changed during replay")
    receipt = dict(scope="retained_reliability_chart_replay_not_scenario_acceptance",
                   source_run=str(run_folder.resolve()), source_sha256=hashes,
                   materializer_version=materializer.MATERIALIZER_VERSION,
                   materializer_sha256=sha256(Path(materializer.__file__)), charts=records)
    (output_folder / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    print(f"RELIABILITY_REPLAY_FOLDER={output_folder.resolve()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_folder", type=Path)
    parser.add_argument("output_folder", type=Path, help="New folder; existing folders are rejected")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--constellation-layers-only", action="store_true")
    selection.add_argument("--sinr-timeline-only", action="store_true")
    selection.add_argument("--reliability-only", action="store_true")
    args = parser.parse_args()
    if args.reliability_only:
        replay_reliability(args.run_folder, args.output_folder)
    elif args.sinr_timeline_only:
        replay_sinr_timeline(args.run_folder, args.output_folder)
    elif args.constellation_layers_only:
        replay_constellation_layers(args.run_folder, args.output_folder)
    else:
        replay(args.run_folder, args.output_folder)
