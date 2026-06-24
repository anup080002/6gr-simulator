from __future__ import annotations

import pandas as pd
from fastapi import APIRouter, HTTPException

from services.csv_store import find_run_dir, load_csv
from services.oracle_guard import scan_oracle_violations

router = APIRouter(tags=["functions"])

REQUIRED_FUNCTIONS = [
    {"module": "sixgr.utils", "function": "exportWithTimeout", "prompt": 1, "category": "infrastructure"},
    {"module": "sixgr.link", "function": "updateLinkAdaptationState", "prompt": 1, "category": "link_adaptation"},
    {"module": "sixgr.phy.broadcast", "function": "recoverSIB1FromWaveform", "prompt": 2, "category": "initial_access"},
    {"module": "sixgr.phy.broadcast", "function": "deriveType0PDCCHFromMIB", "prompt": 2, "category": "initial_access"},
    {"module": "sixgr.phy.prach", "function": "generatePRACHWaveform", "prompt": 2, "category": "random_access"},
    {"module": "sixgr.phy.prach", "function": "detectPRACHWaveform", "prompt": 2, "category": "random_access"},
    {"module": "sixgr.phy.ra", "function": "runFourStepRA", "prompt": 2, "category": "random_access"},
    {"module": "sixgr.phy.pdcch", "function": "encodeDCIPayload", "prompt": 3, "category": "control_plane"},
    {"module": "sixgr.phy.pdcch", "function": "decodeDCIPayload", "prompt": 3, "category": "control_plane"},
    {"module": "sixgr.phy.dl", "function": "PDCCH_Tx", "prompt": 3, "category": "control_plane"},
    {"module": "sixgr.phy.dl", "function": "PDCCH_Rx", "prompt": 3, "category": "control_plane"},
    {"module": "sixgr.link", "function": "runTRSTracking", "prompt": 4, "category": "tracking"},
    {"module": "sixgr.phy.ul", "function": "SRS_Rx", "prompt": 4, "category": "sounding"},
    {"module": "sixgr.channel", "function": "runStrictChannelRFValidation", "prompt": 4, "category": "channel_rf"},
    {"module": "sixgr.mimo", "function": "resolveNominalVsEffectiveMIMO", "prompt": 5, "category": "mimo"},
    {"module": "sixgr.mimo", "function": "selectPMI", "prompt": 5, "category": "mimo"},
    {"module": "sixgr.mimo", "function": "selectULBeamFromSRS", "prompt": 5, "category": "mimo"},
    {"module": "sixgr.l2.mac", "function": "HARQEntity", "prompt": 6, "category": "harq"},
    {"module": "sixgr.l2.mac", "function": "SchedulerPF", "prompt": 6, "category": "scheduler"},
    {"module": "sixgr.util", "function": "resolveTDDSlotPartition", "prompt": 6, "category": "scheduler"},
    {"module": "sixgr.phy.ul", "function": "PUCCH_Rx", "prompt": 7, "category": "control_plane"},
    {"module": "sixgr.phy.pucch", "function": "exportStrictPUCCHArtifacts", "prompt": 7, "category": "evidence"},
    {"module": "sixgr.config", "function": "buildParameterBindingMatrix", "prompt": 7, "category": "config"},
    {"module": "sixgr.analytics", "function": "measureHARQCombiningGain", "prompt": 8, "category": "harq"},
    {"module": "sixgr.truth", "function": "exportLLSHARQDiagnostics", "prompt": 8, "category": "harq"},
    {"module": "sixgr.analytics", "function": "buildMobilityAdequacyReport", "prompt": 8, "category": "mobility"},
    {"module": "sixgr.truth", "function": "buildProvenanceManifest", "prompt": 8, "category": "provenance"},
    {"module": "sixgr.audit", "function": "verifyMeasurementOnly", "prompt": 9, "category": "audit"},
]


@router.get("/functions/{run_id}/missed")
async def get_missed_functions(run_id: str):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    called = set()
    edge_path = run_dir / "reports" / "csv" / "runtime_function_call_edges.csv"
    if edge_path.exists():
        edges = pd.read_csv(edge_path)
        for col in ["CallerFunctionName", "CalleeFunctionName"]:
            if col in edges.columns:
                called.update(str(v) for v in edges[col].dropna().tolist())
    impl_rows = load_csv(run_dir / "reports" / "csv" / "lls_implementation_register.csv")
    impl_map = {str(row.get("output_name", "")): row for row in impl_rows}
    oracle_violations = scan_oracle_violations(run_dir)
    results = []
    for req in REQUIRED_FUNCTIONS:
        function = req["function"]
        full_name = f"{req['module']}.{function}"
        is_called = any(function.lower() in name.lower() for name in called)
        impl = impl_map.get(function, {})
        impl_status = str(impl.get("implementation_status", "") or "")
        status = "CALLED" if is_called else "BYPASSED" if "bypass" in impl_status.lower() else "NOT_CALLED" if impl else "MISSING"
        results.append(
            {
                **req,
                "full_name": full_name,
                "called": is_called,
                "status": status,
                "impl_status": impl_status or "unknown",
                "evidence": impl.get("evidence_status", ""),
                "api_exposed": bool(impl.get("api_exposed_flag", False)),
                "writer_on": bool(impl.get("writer_enabled", False)),
                "blocker": impl.get("blocker_reason", ""),
                "next_step": impl.get("next_implementation_step", ""),
                "oracle_violation": False,
            }
        )
    summary = {
        "total": len(results),
        "called": sum(1 for row in results if row["status"] == "CALLED"),
        "missing": sum(1 for row in results if row["status"] == "MISSING"),
        "not_called": sum(1 for row in results if row["status"] == "NOT_CALLED"),
        "bypassed": sum(1 for row in results if row["status"] == "BYPASSED"),
        "oracle_violations": len(oracle_violations),
    }
    return {"functions": results, "summary": summary, "oracle_violations": oracle_violations}

