"""Residual HARQ plots from unique-TB lifecycle plus independent decoder rows."""
import math
from collections import defaultdict

from lls_harq_terminal_metrics import reconcile, _key


def terminal_bler_chart(chart_name, existing, fetch, run_id):
    import lls_contract_materializer as m
    tx_path = "harq/csv/harq_transmitter_lifecycle.csv"
    _, tx = m._artifact_rows_by_path(existing, fetch, tx_path)
    rx_path, rx = m._first_available_rows(existing, fetch, [
        "harq/csv/harq_process_timeline.csv", "harq/csv/probe_harq_packets.csv"])
    if not tx:
        reason = ("Actual transmitter lifecycle is absent. Receiver attempts alone cannot "
                  "identify terminal retry-limit failures or right-censored transport blocks.")
        return dict(csv_bytes=m._encode_csv(["status", "reason"], [["unavailable_exact_reason", reason]]),
            img_bytes=m._render_reason_svg(chart_name, reason, [tx_path]),
            csv_status="unavailable_exact_reason", image_status="generated_unavailable_reason_svg",
            source_table_path=rx_path, source_row_count=len(rx), note=reason)
    packets, summaries = reconcile(tx, rx)
    by_process = chart_name == "residual BLER by HARQ process"
    if by_process:
        summaries = []
        processes = sorted({int(float(row["HARQProcessId"])) for row in tx})
        for process in processes:
            subset = [row for row in tx if int(float(row["HARQProcessId"])) == process]
            keys = {_key(row) for row in subset}
            _, grouped = reconcile(subset, [row for row in rx if _key(row) in keys])
            for row in grouped:
                row["HARQProcessId"] = process
            summaries.extend(grouped)
    sources = "|".join(path for path in [tx_path, rx_path] if path)
    series = defaultdict(list)
    x_label = "HARQ process" if by_process else "Configured reference SNR (dB)"
    y_label = "Residual BLER / unresolved-outcome bounds"
    rows = []
    for row in summaries:
        x = row["HARQProcessId"] if by_process else row["ConfiguredSNR_dB"]
        label = f'{row["Direction"]} p{row["SweepPointIndex"]} {row["ConfiguredSNR_dB"]:g}dB'
        if math.isfinite(row["ResidualBLER"]):
            series[label+" residual"].append([x, row["ResidualBLER"]])
        else:
            series[label+" lower bound"].append([x, row["ResidualBLERLowerBound"]])
            series[label+" upper bound"].append([x, row["ResidualBLERUpperBound"]])
        rows.append(dict(run_id=run_id, chart_name=chart_name, chart_mode="scatter",
            x_label=x_label, y_label=y_label, x_value=x, y_value=row["ResidualBLER"],
            series_name=label, source_table_logical_path=sources, **row))
    note = ("TB-level receiver CRC; ACK is not data success. "
            "Bounds show unfinished/unknown outcomes, not confidence intervals.")
    shape = "operating_point" if len({row["x_value"] for row in rows}) == 1 else "observed_relation"
    for row in rows:
        row["evidence_shape_policy"] = shape
    return dict(csv_bytes=m._encode_dict_rows(list(rows[0]), rows),
        img_bytes=m._render_multi_series_svg(chart_name, note,
            [dict(name=label, points=points) for label, points in series.items()],
            [f"unique_transmitted_tbs={len(packets)}", f"source_table={sources}"],
            x_label=x_label, y_label=y_label, mode="scatter", show_all_series=True,
            pad_constant_axes=True, evidence_shape_policy=shape, y_bounds=(0.0, 1.0)),
        csv_status="derived_chart_dataset", image_status="generated_specialized_runtime_summary_svg",
        source_table_path=sources, source_row_count=len(tx)+len(rx), note=note,
        source_mapping_status="exact",
        uniform_runtime_evidence_is_valid=True)


def main():
    """Render a fresh diagnostic directory without changing retained evidence."""
    import argparse
    import json
    from pathlib import Path
    import lls_contract_materializer as m
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    run, output = args.run.resolve(), args.output.resolve()
    if not run.is_dir() or output == run or output.is_relative_to(run):
        parser.error("Use an existing run and a new output directory outside that retained run.")
    paths = ["harq/csv/harq_transmitter_lifecycle.csv", "harq/csv/harq_process_timeline.csv",
             "harq/csv/probe_harq_packets.csv"]
    existing, payloads = {}, {}
    for index, path in enumerate(paths):
        if (run/path).is_file():
            existing[path] = dict(artifact_id=index, logical_path=path)
            payloads[index] = (run/path).read_bytes()
    charts = [("residual BLER after HARQ", "residual_bler"),
              ("residual BLER by HARQ process", "residual_bler_by_process")]
    results = [(stem, terminal_bler_chart(name, existing, payloads.__getitem__, 0)) for name, stem in charts]
    output.mkdir(parents=True, exist_ok=False)
    receipt = []
    for stem, result in results:
        (output/(stem+".csv")).write_bytes(result["csv_bytes"])
        # No image is manufactured when lifecycle evidence is absent.
        if result["csv_status"] == "derived_chart_dataset":
            (output/(stem+".png")).write_bytes(m._rasterize_contract_png(result["img_bytes"]))
        receipt.append(dict(chart=stem, status=result["csv_status"], source=result["source_table_path"]))
    print(json.dumps(dict(output=str(output), charts=receipt)))


if __name__ == "__main__":
    main()
