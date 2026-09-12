"""Validate executed data weights and render their exported angular samples.

This module never converts PMI into a matrix or computes replacement gains.
"""
from __future__ import annotations

import hashlib
import html
import math
import struct
from collections import defaultdict


def _number(row, name):
    value = float(row[name])
    if not math.isfinite(value):
        raise ValueError(f"Applied beam requires finite {name}")
    return value


def _index(row, name):
    value = _number(row, name)
    if value < 0 or value != int(value):
        raise ValueError(f"Applied beam requires a nonnegative integer {name}")
    return int(value)


def _key(row):
    identity = row.get("TransmissionID", "").strip()
    if not identity:
        raise ValueError("Applied beam requires an executed transmission identity")
    return identity, _index(row, "PRGIndex0"), _index(row, "SymbolGroupIndex0")


def validate_samples(weight_rows, pattern_rows):
    if not weight_rows or not pattern_rows:
        raise ValueError("Applied beam requires exact executed weights AND angular samples; PMI is not a matrix")
    matrices = defaultdict(list)
    for row in weight_rows:
        if row.get("Source") != "executed_data_precoder_mapping_shared_transmission_started" or row.get("ReferencePlane") != "physical_element_data_grid_before_node_rf":
            raise ValueError("Applied beam weight provenance is not executed pre-RF data mapping")
        matrices[_key(row)].append(row)
    metadata = {}
    for key, rows in matrices.items():
        start = _index(rows[0], "StartSample")
        end = _index(rows[0], "EndSampleExclusive")
        if end <= start or _number(rows[0], "SampleRate_Hz") <= 0 or _number(rows[0], "Frequency_Hz") <= 0:
            raise ValueError("Applied beam requires valid physical time/frequency coordinates")
        if (rows[0].get("Direction"), rows[0].get("Signal")) not in {("DL", "PDSCH"), ("UL", "PUSCH")}:
            raise ValueError("Applied beam requires an explicit DL/PDSCH or UL/PUSCH identity")
        cells = {}
        positions = {}
        for row in rows:
            index = _index(row, "ElementIndex0"), _index(row, "LayerIndex0")
            if index in cells:
                raise ValueError("Duplicate applied beam coefficient")
            cells[index] = complex(_number(row, "WeightReal"), _number(row, "WeightImag"))
            pos = tuple(_number(row, name) for name in ("ElementX_m", "ElementY_m", "ElementZ_m"))
            if index[0] in positions and positions[index[0]] != pos:
                raise ValueError("Applied beam element positions change between layers")
            positions[index[0]] = pos
        ports = max(k[0] for k in cells) + 1
        layers = max(k[1] for k in cells) + 1
        if set(cells) != {(p, l) for p in range(ports) for l in range(layers)}:
            raise ValueError("Incomplete applied beam matrix")
        values = [cells[p, l] for l in range(layers) for p in range(ports)]
        header = f"sixgr-mimo-matrix-v1|double|[{ports} {layers}]|".encode()
        payload = struct.pack(f"<{len(values)}d", *(v.real for v in values))
        payload += struct.pack(f"<{len(values)}d", *(v.imag for v in values))
        digest = hashlib.sha256(header + payload).hexdigest()
        for row in rows:
            if row.get("MatrixDigestConvention") != "sixgr-mimo-matrix-v1" or row.get("MatrixSHA256", "").lower() != digest:
                raise ValueError("Applied beam matrix digest mismatch")
            for name in ("Direction", "Signal", "UEIndex", "PHYGrantContextId", "StartSample", "EndSampleExclusive", "SampleRate_Hz", "Frequency_Hz"):
                if row.get(name) != rows[0].get(name):
                    raise ValueError(f"Mixed applied beam identity: {name}")
        metadata[key] = rows[0], layers, digest
    grids = defaultdict(dict)
    for row in pattern_rows:
        key = _key(row)
        if key not in metadata:
            raise ValueError("Angular samples have no matching executed matrix")
        source, layers, digest = metadata[key]
        layer = _index(row, "LayerIndex0")
        if layer >= layers or row.get("MatrixSHA256", "").lower() != digest or row.get("MatrixDigestConvention") != "sixgr-mimo-matrix-v1":
            raise ValueError("Angular samples do not match the applied layer/matrix")
        for name in ("Direction", "Signal", "UEIndex", "PHYGrantContextId", "StartSample", "EndSampleExclusive", "SampleRate_Hz", "Frequency_Hz"):
            if row.get(name) != source.get(name):
                raise ValueError(f"Angular sample identity mismatch: {name}")
        if row.get("PatternKind") != "data_precoder_directivity_before_node_rf" or row.get("PatternSource") != "executed_matrix_and_installed_NRRectangularPanelArray":
            raise ValueError("Angular samples are not from the actual applied data precoder")
        if str(row.get("SelectedBeamApplied", "")).lower() not in {"1", "true"} or str(row.get("OverTheAirMeasurement", "")).lower() not in {"0", "false"}:
            raise ValueError("Applied pattern/OTA measurement roles are inconsistent")
        if row.get("CoordinateFrame") != "local_array_before_runtime_orientation":
            raise ValueError("Applied pattern coordinate frame is not supported")
        az, el = _number(row, "Azimuth_deg"), _number(row, "Elevation_deg")
        gain = float(row["Directivity_dBi"])
        if not (-180 <= az <= 180 and -90 <= el <= 90) or math.isnan(gain) or gain == math.inf:
            raise ValueError("Invalid applied pattern angle/directivity")
        group = key + (layer,)
        if (az, el) in grids[group]:
            raise ValueError("Duplicate applied pattern angular sample")
        grids[group][az, el] = gain
    expected = {key + (layer,) for key, (_, layers, _) in metadata.items() for layer in range(layers)}
    if set(grids) != expected:
        raise ValueError("Some executed matrix layers have no angular samples")
    for grid in grids.values():
        az = {p[0] for p in grid}; el = {p[1] for p in grid}
        if len(az) < 2 or len(el) < 2 or set(grid) != {(a, e) for a in az for e in el} or not any(math.isfinite(v) for v in grid.values()):
            raise ValueError("Incomplete applied beam angular grid")
    # Representative view only: latest actual TX, then explicit PRG/group/layer.
    selected = sorted(grids, key=lambda k: (-float(metadata[k[:3]][0]["StartSample"]), k))[0]
    return grids[selected], metadata[selected[:3]][0], selected


def render_surface(grid, source, selected, title):
    """Projected 3D power-radius surface; the original CSV remains unchanged."""
    azimuths = sorted({p[0] for p in grid}); elevations = sorted({p[1] for p in grid})
    peak = max(grid.values())
    yaw, pitch = math.radians(35), math.radians(20)

    def project(x, y, z):
        right = math.cos(yaw)*x - math.sin(yaw)*y
        depth = math.sin(yaw)*x + math.cos(yaw)*y
        up = math.cos(pitch)*z - math.sin(pitch)*depth
        return 370 + 220*right, 300 - 220*up, math.sin(pitch)*z + math.cos(pitch)*depth

    vertices = {}
    for (az, el), gain in grid.items():
        radius = 0 if gain == -math.inf else 10**((gain-peak)/10)
        a, e = math.radians(az), math.radians(el)
        vertices[az, el] = project(radius*math.cos(e)*math.cos(a), radius*math.cos(e)*math.sin(a), radius*math.sin(e))
    faces = []
    for i in range(len(azimuths)-1):
        for j in range(len(elevations)-1):
            corners = [(azimuths[i], elevations[j]), (azimuths[i+1], elevations[j]), (azimuths[i+1], elevations[j+1]), (azimuths[i], elevations[j+1])]
            points = [vertices[p] for p in corners]
            relative = max(grid[p] for p in corners)-peak
            color = max(0, min(1, (relative+40)/40))
            fill = f"rgb({int(245*color)},{int(90+90*(1-abs(2*color-1)))},{int(230*(1-color))})"
            polygon = " ".join(f"{x:.3f},{y:.3f}" for x,y,_ in points)
            faces.append((sum(p[2] for p in points)/4, f'<polygon points="{polygon}" fill="{fill}" stroke="#345" stroke-width="0.2"/>'))
    details = f'{source["Signal"]} UE {source["UEIndex"]}; start sample {source["StartSample"]}; PRG/group/layer {selected[1:]}; peak {peak:.3f} dBi'
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="760" height="620" viewBox="0 0 760 620">', '<rect width="760" height="620" fill="white"/>', f'<text x="20" y="28" font-family="sans-serif" font-size="18">{html.escape(title)}</text>', f'<text x="20" y="52" font-family="sans-serif" font-size="12">{html.escape(details)}</text>']
    svg.extend(face for _,face in sorted(faces))
    for label, direction in (("x",(1,0,0)),("y",(0,1,0)),("z",(0,0,1))):
        x,y,_=project(*direction)
        svg.append(f'<line x1="370" y1="300" x2="{x}" y2="{y}" stroke="#222"/><text x="{x+5}" y="{y}" font-family="sans-serif">{label}</text>')
    svg.append('<text x="20" y="570" font-family="sans-serif" font-size="12">Local-array 3D directivity; pre-node-RF computed pattern, not an OTA measurement.</text>')
    svg.append('<text x="20" y="590" font-family="sans-serif" font-size="12">Radius = power / sampled peak. Color spans -40 to 0 dB relative to sampled peak.</text></svg>')
    return "".join(svg).encode("utf-8")
