from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd

BAD_NOISE_TOKENS = {"configured_snr", "synthetic", "fallback", "oracle", "perfect"}
BAD_CHANNEL_METHOD_TOKENS = {"perfect", "oracle", "truth_channel", "genie"}


def _as_text(value: Any) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except Exception:
        pass
    return str(value).strip()


def scan_oracle_violations(run_dir: Path) -> list[dict[str, Any]]:
    violations: list[dict[str, Any]] = []
    for path in run_dir.rglob("*.csv"):
        rel = path.relative_to(run_dir).as_posix()
        if not any(part in rel for part in ("air_interface/", "control/", "reports/")):
            continue
        try:
            df = pd.read_csv(path)
        except Exception:
            continue
        for idx, row in df.iterrows():
            used_oracle = _as_text(row.get("UsedOracleFields", ""))
            if used_oracle:
                violations.append(
                    {
                        "artifact": rel,
                        "row": int(idx) + 2,
                        "field": "UsedOracleFields",
                        "value": used_oracle,
                        "reason": "Oracle fields must not feed measurement-only WebGUI outputs.",
                    }
                )
            noise_source = _as_text(row.get("NoiseVarSource", "")).lower()
            if any(token in noise_source for token in BAD_NOISE_TOKENS):
                violations.append(
                    {
                        "artifact": rel,
                        "row": int(idx) + 2,
                        "field": "NoiseVarSource",
                        "value": noise_source,
                        "reason": "Noise evidence source is configured/proxy/oracle-like.",
                    }
                )
            channel_method = _as_text(row.get("ChannelEstMethod", "")).lower()
            if any(token in channel_method for token in BAD_CHANNEL_METHOD_TOKENS):
                violations.append(
                    {
                        "artifact": rel,
                        "row": int(idx) + 2,
                        "field": "ChannelEstMethod",
                        "value": channel_method,
                        "reason": "Channel-estimation method is perfect/oracle-like.",
                    }
                )
    return violations

