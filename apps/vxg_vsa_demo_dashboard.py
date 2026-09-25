"""Offline exhibit builder/launcher for immutable, actual lab-waveform evidence."""
import argparse
import functools
import http.server
import json
import shutil
import webbrowser
from pathlib import Path


def validate_physical(data, expected):
    """Imported RF evidence must identify its instrument, units and measurement scope."""
    required=("schema_version","evidence_mode","instrument_idn","captured_utc","direction",
              "profile","carrier_hz","bandwidth_hz","rank","measurement_scope","metrics")
    if any(k not in data for k in required):
        raise ValueError("Incomplete physical measurement identity/scope")
    if data["schema_version"]!=1 or data["evidence_mode"]!="physical_rf" or not data["instrument_idn"]:
        raise ValueError("Not a declared physical RF capture")
    from datetime import datetime
    stamp=datetime.fromisoformat(data["captured_utc"].replace("Z","+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("Physical timestamp must include a timezone")
    if data["direction"] not in ("DL","UL") or data["profile"] not in expected["profiles"]:
        raise ValueError("Physical capture belongs to a different campaign")
    config=expected["config"]
    if (data["carrier_hz"]!=config["frequency"]["center_frequency_hz"] or
        data["bandwidth_hz"]!=config["frequency"]["bandwidth_hz"] or data["rank"]!=config["mimo"]["n_layers"]):
        raise ValueError("Physical carrier/bandwidth/rank does not match digital reference")
    # Comparisons are allowed only on an explicitly identical basis, not inferred from units.
    import math
    definitions={"evm_rms":{"unit":"percent","definition":"sqrt_sum_error_energy_over_sum_reference_energy"},
                 "papr":{"unit":"dB","definition":"peak_over_full_frame_mean_power"},
                 "power":{"unit":"dBm","definition":"mean_rf_power"},
                 "frequency_error":{"unit":"Hz","definition":"measured_carrier_minus_configured_carrier"}}
    for name,value in data["metrics"].items():
        if name not in definitions or not isinstance(value,dict) or not isinstance(value.get("value"),(int,float)) or not math.isfinite(value["value"]):
            raise ValueError("Unknown or nonfinite physical measurement")
        if any(value.get(k)!=v for k,v in definitions[name].items()):
            raise ValueError(f"Incompatible physical metric units/definition: {name}")
    if not data["metrics"] or data["measurement_scope"] not in ("per_layer_data_re","per_port_full_frame"):
        raise ValueError("Missing measurements or incompatible measurement scope")
    if "layer_or_port" in data and (type(data["layer_or_port"]) is not int or not 1<=data["layer_or_port"]<=data["rank"]):
        raise ValueError("Physical layer/port identity outside configured rank")
    return data


def load_physical_files(root,data):
    """Optional measured traces: strict paths, file hashes, columns and units."""
    import hashlib
    import numpy as np
    import pandas as pd
    definitions={"constellation":(("I","Q"),{"normalized_reference_symbol"}),
                 "evm":(("SymbolIndex","EVMRMSPercent"),{"percent"}),
                 "spectrum":(("FrequencyHz","PowerDensity"),{"dBm/Hz","W/Hz"}),
                 "ccdf":(("Threshold_dB","Exceedance"),{"probability"})}
    root=Path(root).resolve(); traces={}
    for kind,entry in data.get("files",{}).items():
        if kind not in definitions or not isinstance(entry,dict):
            raise ValueError("Unsupported physical trace kind")
        path=(root/entry.get("path","")).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Physical trace path is missing or escapes the run folder")
        if hashlib.sha256(path.read_bytes()).hexdigest()!=entry.get("sha256"):
            raise ValueError("Physical trace hash mismatch")
        columns,units=definitions[kind]
        if entry.get("unit") not in units:
            raise ValueError("Physical trace units are incompatible")
        table=pd.read_csv(path)
        if not set(columns).issubset(table.columns) or table.empty:
            raise ValueError("Physical trace columns/population incomplete")
        values=table[list(columns)].to_numpy(dtype=float)
        if not np.isfinite(values).all():
            raise ValueError("Physical trace contains nonfinite values")
        if kind=="ccdf" and ((values[:,1]<0)|(values[:,1]>1)).any():
            raise ValueError("Physical CCDF outside probability range")
        if kind=="evm" and (values[:,1]<0).any():
            raise ValueError("Negative physical EVM")
        indices=np.unique(np.linspace(0,len(values)-1,min(8192,len(values))).astype(int))
        traces[kind]={"columns":list(columns),"unit":entry["unit"],"values":values[indices].tolist(),
                      "total":len(values),"displayed":len(indices),"source":entry["path"],"sha256":entry["sha256"]}
    return traces


def build_dashboard(root,replay=None):
    root=Path(root).resolve()
    if (root/"manifest.json").exists():
        raise ValueError("Sealed package is immutable; use a new package for changed presentation or physical capture")
    if replay is None:
        replay=json.loads((root/"webgui/replay_data.json").read_text(encoding="utf-8"))
    # Summary values use every measured PSD bin, not the display subsample.
    import numpy as np
    import pandas as pd
    for profile in replay["profiles"].values():
        for item in profile.values():
            for port in item["ports"]:
                psd=pd.read_csv(root/port["csv"])["PSD_per_Hz"].to_numpy(dtype=float)
                if not np.isfinite(psd).all() or (psd<0).any() or psd.max()<=0:
                    raise ValueError("Invalid measured PSD population")
                port["stats"]["PeakPSDdBPerHz"]=float(10*np.log10(psd.max()))
    physical_path=root/"physical_measurement.json"
    replay["physical"]=validate_physical(json.loads(physical_path.read_text(encoding="utf-8")),replay) if physical_path.exists() else None
    if replay["physical"] is not None:
        replay["physical"]["traces"]=load_physical_files(root,replay["physical"])
    template=Path(__file__).with_name("vxg_vsa_demo.html").read_text(encoding="utf-8")
    embedded=json.dumps(replay,separators=(",",":"),allow_nan=False).replace("</","<\\/")
    html=template.replace("/*__REPLAY_DATA__*/",embedded)
    package=root/"demo_package"; package.mkdir(exist_ok=True)
    for directory in (root/"webgui",package):
        (directory/"index.html").write_text(html,encoding="utf-8")
        (directory/"replay_data.json").write_text(json.dumps(replay,allow_nan=False),encoding="utf-8")
        (directory/"scenario_summary.json").write_text(json.dumps(replay["summary"],indent=2),encoding="utf-8")
        (directory/"instrument_handoff.json").write_text(json.dumps(replay["handoff"],indent=2),encoding="utf-8")
        shutil.copy2(root/"validation/package_receipt.json",directory/"validation_receipt.json")
    # A presentation-only rebuild retains its own exact source version; it does
    # not overwrite the original waveform-packaging source snapshot.
    sources=root/"meta/dashboard_sources"; sources.mkdir(exist_ok=True)
    for name in ("vxg_vsa_demo_dashboard.py","vxg_vsa_demo.html"):
        shutil.copy2(Path(__file__).with_name(name),sources/name)
    return package


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("run_folder",type=Path)
    p.add_argument("--build-only",action="store_true"); p.add_argument("--port",type=int,default=8991)
    args=p.parse_args()
    if (args.run_folder/"manifest.json").exists() and not args.build_only:
        # Serving a sealed package must never rewrite its validated bytes.
        folder=args.run_folder/"demo_package"
    else:
        folder=build_dashboard(args.run_folder)
    if args.build_only:
        print(folder/"index.html"); return
    handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(args.run_folder.resolve()))
    server=http.server.ThreadingHTTPServer(("127.0.0.1",args.port),handler)
    url=f"http://127.0.0.1:{args.port}/webgui/"; print(url,flush=True); webbrowser.open(url)
    server.serve_forever()


if __name__=="__main__": main()
