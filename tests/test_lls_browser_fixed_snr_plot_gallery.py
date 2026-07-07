from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def test_reference_gallery_matches_fixed_snr_plot_filenames() -> None:
    gallery = dash.build_reference_plot_gallery(
        numeric_charts=[],
        image_descriptors=[
            {
                "artifact_id": 1,
                "logical_path": "reports/image/dl_bler_vs_snr.png",
                "artifact_kind": "image_png",
                "section": "reports",
            },
            {
                "artifact_id": 2,
                "logical_path": "reports/image/dl_ber_vs_snr.png",
                "artifact_kind": "image_png",
                "section": "reports",
            },
            {
                "artifact_id": 3,
                "logical_path": "reports/image/dl_throughput_vs_snr.png",
                "artifact_kind": "image_png",
                "section": "reports",
            },
            {
                "artifact_id": 4,
                "logical_path": "reports/image/measured_sinr_vs_configured_snr.png",
                "artifact_kind": "image_png",
                "section": "reports",
            },
        ],
    )

    item_map = {str(item["label"]): item for item in gallery["items"]}

    assert item_map["bler_vs_sinr"]["status"] == "image"
    assert str(item_map["bler_vs_sinr"]["image"]["logical_path"]).endswith("dl_bler_vs_snr.png")

    assert item_map["ber_vs_snr"]["status"] == "image"
    assert str(item_map["ber_vs_snr"]["image"]["logical_path"]).endswith("dl_ber_vs_snr.png")

    assert item_map["throughput_vs_snr"]["status"] == "image"
    assert str(item_map["throughput_vs_snr"]["image"]["logical_path"]).endswith("dl_throughput_vs_snr.png")

    assert item_map["measured_sinr_vs_configured_snr"]["status"] == "image"
    assert str(item_map["measured_sinr_vs_configured_snr"]["image"]["logical_path"]).endswith(
        "measured_sinr_vs_configured_snr.png"
    )
