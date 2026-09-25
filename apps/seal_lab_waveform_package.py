"""Final read-only evidence audit followed by an immutable artifact inventory."""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
import pandas as pd
from build_lab_waveform_package import digest, require, write_json


def verify(root):
    """Read-only verification after copying the sealed package to another PC."""
    root=Path(root).resolve()
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    require(manifest["Status"]=="digital_package_complete","Package is not complete")
    expected=set()
    for row in manifest["Artifacts"]:
        path=(root/row["Path"]).resolve()
        require(path.is_relative_to(root) and path.is_file(),"Missing or invalid package artifact")
        require(path.stat().st_size==row["Bytes"] and digest(path)==row["SHA256"],f"Changed artifact: {row['Path']}")
        require(row["Path"] not in expected,"Duplicate manifest artifact")
        expected.add(row["Path"])
    actual={p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p!=root/"manifest.json"}
    require(actual==expected,"Package contains unlisted or missing artifacts")
    print(f"SEALED_PACKAGE_VERIFIED: {len(expected)} artifact hashes; manifest SHA256={digest(root/'manifest.json')}")
    return manifest


def seal(root):
    root=Path(root).resolve()
    meta=json.loads((root/"meta/manifest.json").read_text(encoding="utf-8-sig"))
    require(meta["Status"]=="phy_completed","PHY execution incomplete")
    browser=json.loads((root/"validation/browser_receipt.json").read_text(encoding="utf-8"))
    require(browser["Passed"] and browser["SourceRun"]==meta["RunTag"],"Browser not verified against this run")
    for name in ("index.html","replay_data.json","demo_dashboard_1920x1080.png"):
        require(browser.get("CheckedFiles",{}).get(name)==digest(root/"webgui"/name),
                "Browser artifact changed or was not hashed; repeat browser acceptance")
    receipts=json.loads((root/"validation/export_receipts.json").read_text(encoding="utf-8"))
    require(len(receipts)>0,"No exports")
    for row in receipts:
        path=(root/row["Path"]).resolve()
        require(path.is_relative_to(root) and path.is_file(),"Invalid export path")
        require(path.stat().st_size==row["Bytes"] and digest(path)==row["SHA256"],f"Changed export: {path}")
        require(row["ExactReadback"] and not row["Resampled"] and row["ClippedComponents"]==0,"Failed export gate")
    expected=("dl_time_iq","ul_time_iq","dl_psd","ul_psd","dl_spectrum","ul_spectrum", "dl_papr_ccdf","ul_papr_ccdf",
              "dl_constellation_reference","ul_constellation_reference","dl_constellation_awgn_30db","ul_constellation_awgn_30db",
              "resource_grid_dl","resource_grid_ul","tdd_timeline","evm_per_symbol","evm_per_prb")
    for name in expected:
        require((root/"reports/image"/f"{name}.png").is_file(),f"Missing required image: {name}")
    for name in ("scenario_summary","iq_statistics","throughput","evm","papr","psd","instrument_handoff"):
        path=root/"reports/csv"/f"{name}.csv"
        require(path.is_file() and len(pd.read_csv(path))>0,f"Missing measurement table: {name}")
    require((root/"webgui/demo_dashboard_1920x1080.png").is_file(),"Missing actual dashboard screenshot")
    shutil.copy2(root/"webgui/demo_dashboard_1920x1080.png",root/"demo_package/demo_dashboard_1920x1080.png")
    receipt=json.loads((root/"validation/package_receipt.json").read_text(encoding="utf-8"))
    receipt.update(WebDemoReady=True,SoftwareHandoffReady=True,InstrumentCapability="UNKNOWN",
                   PhysicalInstrumentCapabilityVerified="UNKNOWN",SealerSHA256=digest(Path(__file__)))
    write_json(root/"validation/package_receipt.json",receipt)
    for folder in ("webgui","demo_package"):
        write_json(root/folder/"validation_receipt.json",receipt)
    summary=pd.read_csv(root/"reports/csv/throughput.csv")
    config=json.loads((root/"config/resolved_config.json").read_text(encoding="utf-8-sig"))
    report=["# Completed digital waveform engineering report", "",meta["Description"], "",
            f"Source commit: `{meta['GitCommit']}`; dirty at execution: `{meta['GitDirty']}`. Exact executed source snapshots are retained.",
            f"Scenario: `{meta['ScenarioID']}`; run: `{meta['RunTag']}`; MATLAB: `{meta['MATLAB']}`.",
            f"Carrier: {config['frequency']['center_frequency_hz']/1e9:g} GHz; nominal BW {config['frequency']['bandwidth_hz']/1e6:g} MHz (research).",
            f"Fs {meta['SampleRateHz']:g} samples/s; FFT {meta['FFTSize']}; SCS {config['frame']['scs_khz']} kHz; normal CP.",
            f"{meta['SamplesPerPort']:,} complex samples/port; {meta['SamplesPerPort']/meta['SampleRateHz']*1000:g} ms; 264 PRBs; two ports/two layers in both directions.",
            "DMRS Type1 / length1 / Type-A position2 / additionalPosition1 / ports[0,1] / NID1 / nSCID0; full-slot data only.",
            "Configured timing, identity MIMO, received-DMRS estimation/MMSE, genuine TBS/LDPC/CRC. No access, physical control, HARQ or link adaptation.",
            "UL is an experimental 1024-QAM waveform; no NR UL MCS index is assigned.", "",
            "| Profile | Direction | SNR dB | TBS | Rate | CRC pass/total | Goodput Gbit/s | RMS EVM % |",
            "|---|---|---:|---:|---:|---:|---:|---:|"]
    for r in summary.itertuples():
        report.append(f"| {r.Profile} | {r.Direction} | {r.SNRdB:g} | {r.TBSBits} | {r.TargetCodeRate:.8f} | {r.CRCPasses}/{r.TBCount} | {r.GoodputGbps:.6f} | {r.EVMRMSPercent:.4f} |")
    report += ["", "All cases are retained; CRC failure is not relabeled success. These finite frame results are not statistical BLER qualification.",
               "PAPR, per-port statistics, PSD, EVM populations and full throughput definitions are in `reports/csv/`.",
               "Raw CSV/MAT, playback WIQ/VSA and hashes: `validation/export_receipts.json` and `keysight/instrument_handoff.json`.",
               "Dashboard: `webgui/index.html`; portable UI: `demo_package/index.html`; screenshot: `webgui/demo_dashboard_1920x1080.png`.",
               "No physical RF data have been generated or fabricated. Installed hardware remains unverified.","",
               "WAVEFORM EXPORT READY: YES", "", "WEB DEMO READY: YES", "", "VXG/VSA SOFTWARE HANDOFF READY: YES", "",
               "PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN", "",
               "PAYLOAD DECODING ACROSS EVERY REQUESTED CASE: "+("PASS" if meta["PayloadPass"] else "FAIL — inspect retained 30/35/40 dB results")]
    report += ["", "## Exact MATLAB invocation", "",
               "Run from the repository root in Windows Command Prompt. Use a new run tag for another execution:", "", "```bat",
               '\"C:\\Program Files\\MATLAB\\R2026a\\bin\\matlab.exe\" -logfile \"logs\\vxg_vsa_repeat.log\" -batch \"setup6GRSimToolkit(\'Verbose\',false); out=run_6g_phy_lls_single(\'simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml\',\'results\',\'vxg_vsa_repeat\'); disp(out);\"',
               "```", "", "For the complete execute/package/browser/seal workflow, see `keysight/hardware_checklist_and_runbook.md`.",
               "", "## Actual native-IQ power and PAPR", "",
               "Power is normalized digital baseband, not dBm. Full-frame means include TDD silence; active-slot means exclude it.", "",
               "| Profile | Direction | Port | RMS | Peak magnitude | Frame PAPR dB | Active-slot PAPR dB |",
               "|---|---|---:|---:|---:|---:|---:|"]
    for r in pd.read_csv(root/"reports/csv/iq_statistics.csv").itertuples():
        report.append(f"| {r.Profile} | {r.Direction} | {r.Port} | {r.RMS:.8f} | {r.PeakMagnitude:.8f} | {r.PAPRFullFrame_dB:.4f} | {r.PAPRActiveSlots_dB:.4f} |")
    report += ["", "## Validated instrument files", "", "All SHA-256 values below identify the read-back-validated bytes; hardware import remains unverified.", "",
               "| Relative file | Bytes | SHA-256 |", "|---|---:|---|"]
    for r in receipts:
        report.append(f"| `{r['Path']}` | {r['Bytes']} | `{r['SHA256']}` |")
    (root/"reports/engineering_report.md").write_text("\n\n".join(report[:12])+"\n"+"\n".join(report[12:]),encoding="utf-8")
    shutil.copy2(Path(__file__),root/"meta/final_sealer_source.py")
    # Include all actual source/data/plots/GUI artifacts; exclude only the inventory itself.
    inventory=[]
    for path in sorted(root.rglob("*")):
        if path.is_file() and path!=root/"manifest.json":
            inventory.append(dict(Path=path.relative_to(root).as_posix(),Bytes=path.stat().st_size,SHA256=digest(path)))
    manifest=dict(Description=meta["Description"],Status="digital_package_complete",RunTag=meta["RunTag"],
                  GitCommit=meta["GitCommit"],GitDirty=meta["GitDirty"],ConfigHash=meta["ConfigHash"],
                  WaveformExportReady=True,WebDemoReady=True,SoftwareHandoffReady=True,
                  PhysicalInstrumentCapabilityVerified="UNKNOWN",PayloadPass=meta["PayloadPass"],
                  StatisticalQualification=False,Artifacts=inventory)
    write_json(root/"manifest.json",manifest)
    print("WAVEFORM EXPORT READY: YES\nWEB DEMO READY: YES\nVXG/VSA SOFTWARE HANDOFF READY: YES\nPHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN")
    print(f"Artifacts: {len(inventory)}, bytes: {sum(x['Bytes'] for x in inventory):,}")
    print("CAMPAIGN PAYLOAD CRC: "+("PASS" if meta["PayloadPass"] else "FAIL — retained 30 dB cases; see reports/csv/throughput.csv"))
    return manifest


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("run_folder",type=Path)
    p.add_argument("--verify-only",action="store_true",help="Read-only verification of the complete inventory after transfer")
    args=p.parse_args()
    (verify if args.verify_only else seal)(args.run_folder)
