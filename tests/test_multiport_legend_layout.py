"""A compact complete key must never hide measured multiport series."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_contract_materializer import _render_multi_series_svg


def test_64_port_evm_keeps_all_128_series_and_all_384_points():
    series = [dict(name=f"CSI-RS TX RF raw gain-inclusive {metric} P{port} U1 C1 (40 dB reference)",
                   points=[[slot, 59 + port / 1000 + shift] for slot in (6, 26, 46)])
              for port in range(64) for metric, shift in (("rms", 0), ("peak", 1))]
    svg = _render_multi_series_svg("CSI-RS EVM", "Raw paired gain-inclusive error, not RF conformance.",
        series, ["source_records=192"], x_label="Executed slot", y_label="EVM (%)",
        mode="scatter", evidence_shape_policy="operating_point", wrap_legend=True,
        wrap_subtitle=True, max_points_per_series=None, pad_constant_axes=True)
    root = ET.fromstring(svg)
    ns = {"s": "http://www.w3.org/2000/svg"}
    assert int(root.attrib["height"]) < 3600  # Old single-column output exceeded 8700 px.
    assert [node.text for node in root.findall(".//s:g/s:title", ns)] == [s["name"] for s in series]
    circles = root.findall(".//s:circle", ns)
    squares = root.findall(".//s:rect", ns)
    points = [node for node in circles if node.attrib["r"] == "2.6"] + [
        node for node in squares if node.attrib.get("width") == node.attrib.get("height") == "6"]
    legend = [node for node in circles if node.attrib["r"] == "3"] + [
        node for node in squares if node.attrib.get("width") == node.attrib.get("height") == "8"]
    assert len(points) == 384 and len(legend) == 128  # All marker shapes, no discarded series.
    assert len({float(node.attrib["cx"]) if "cx" in node.attrib else float(node.attrib["x"]) + 4
                for node in legend}) == 4
    for node in root.findall(".//s:text", ns):
        assert float(node.attrib["y"]) < int(root.attrib["height"])


def test_small_legends_keep_the_existing_side_panel():
    svg = _render_multi_series_svg("Small", "Measured", [dict(name="one", points=[[1, 2]])],
        [], x_label="Slot", y_label="Value", mode="scatter", wrap_legend=True,
        evidence_shape_policy="operating_point", pad_constant_axes=True)
    root = ET.fromstring(svg)
    assert int(root.attrib["height"]) == 720
    assert b"Complete series key" not in svg
