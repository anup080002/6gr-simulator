"""Copy verified per-port arrays into documented multichannel VSA MAT recordings.

Requires numpy/scipy only for packaging, not for offline dashboard playback.
No RF control, waveform regeneration, channel mixing, resampling or noise injection.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat, savemat

from build_recorded_demo import collect, digest, require


def package(run_folder, output_folder):
    root, output = Path(run_folder).resolve(), Path(output_folder).resolve()
    require(not output.exists(), "Use a new output directory; preserve existing recordings")
    evidence = collect(root)
    output.mkdir(parents=True)
    receipts = []
    for direction in ("DL", "UL"):
        for point in ("TX", "RX"):
            ports = sorted((r for r in evidence["iq"] if r["Direction"] == direction and r["CapturePoint"] == point),
                           key=lambda r: int(r["Port"]))
            count = len(ports)
            recording = {"XStart": 0.0}
            header = None
            for r in ports:
                source = loadmat(root / r["VSAMATFile"])
                values = source["Y"]
                require(values.dtype == np.complex64 and values.shape == (evidence["samples"], 1)
                        and np.isfinite(values).all(), "Unexpected normalized complex-single port array")
                current = {key: float(source[key].item()) for key in ("XDelta", "InputCenter", "InputZoom", "XDomain")}
                require(current["XDelta"] == 1 / evidence["sampleRate"] and
                        current["InputCenter"] == evidence["frequency"]["center_frequency_hz"] and
                        current["InputZoom"] == 1 and current["XDomain"] == 2,
                        "Unexpected source recording header")
                require(header is None or current == header, "Port clocks or headers differ")
                header = current
                port = int(r["Port"])
                name = "Y" if count == 1 else f"Y{port}" if count == 2 else f"Y{port}_{count}"
                recording[name] = values
            recording.update(header)
            target = output / f"{direction.lower()}_{point.lower()}_{count}ch_vsa.mat"
            savemat(target, recording, do_compression=False, oned_as="column")
            back = loadmat(target)
            for key, value in recording.items():
                require(np.array_equal(back[key], value if isinstance(value, np.ndarray) else np.array([[value]])),
                        f"MAT readback differs: {key}")
            receipts.append({"Direction": direction, "CapturePoint": point, "Channels": count,
                "File": target.name, "SHA256": digest(target), "SamplesPerChannel": evidence["samples"],
                "SampleRateHz": evidence["sampleRate"], "CenterFrequencyHz": header["InputCenter"],
                "CommonEndpointFullScale": float(ports[0]["CommonEndpointFullScale"]),
                "SourceFiles": [{"Path": r["VSAMATFile"], "SHA256": r["VSAMATSHA256"]} for r in ports],
                "ExactReadback": True, "Resampled": False, "AdditionalNoise": False,
                "InstrumentImportVerified": False, "PowerUnits": "normalized_playback_not_dBm"})
            print(f"EXACT_MULTICHANNEL_READBACK_PASS {direction} {point} channels={count}")
            del recording, back, source, values
    (output / "vsa_recordings.json").write_text(json.dumps({"Status": "completed",
        "SourceCommit": evidence["manifest"]["GitCommit"], "PackagingScriptSHA256": digest(Path(__file__)),
        "SourceFolder": str(root), "InstrumentImportVerified": False, "Recordings": receipts}, indent=2), encoding="utf-8")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_folder", type=Path)
    parser.add_argument("output_folder", type=Path)
    args = parser.parse_args()
    print(package(args.run_folder, args.output_folder))
