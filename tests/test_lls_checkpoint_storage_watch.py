"""Storage-stop policy fixtures. MATLAB/Stop-Process are mocked, never invoked."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest

pytestmark = pytest.mark.skipif(os.name != "nt", reason="Windows process/storage guard")
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/watch_lls_checkpoint_storage.ps1"


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


@pytest.mark.parametrize("condition", ["valid", "bad_hash", "old_checkpoint", "wrong_process", "reused_pid", "inspect"])
def test_stop_requires_exact_process_and_new_hash_verified_checkpoint(tmp_path, condition):
    run = tmp_path / "selected_run"
    (run / "meta").mkdir(parents=True)
    checkpoint = tmp_path / ".checkpoints/selected_run/after_slot_000050"
    checkpoint.mkdir(parents=True)
    state = checkpoint / "state.mat"
    state.write_bytes(b"storage policy fixture only, not a MATLAB checkpoint")
    slot = 45 if condition == "old_checkpoint" else 50
    digest = hashlib.sha256(state.read_bytes()).hexdigest()
    (checkpoint / "checkpoint.json").write_text(json.dumps({
        "Status": "complete", "RunFolder": str(run), "CompletedSlotOneBased": slot,
        "NextSlotOneBased": slot + 1, "StateSHA256": "0" * 64 if condition == "bad_hash" else digest,
    }))
    (run / "meta/latest_slot_checkpoint.json").write_text(json.dumps({
        "Checkpoint": str(state), "CompletedSlotOneBased": slot, "NextSlotOneBased": slot + 1,
    }))
    token = "different_process" if condition == "wrong_process" else "exact_run_token"
    reused = "$true" if condition == "reused_pid" else "$false"
    command = f"""
$ErrorActionPreference='Stop'; $global:calls=0; $global:stopCalled=$false
function global:Get-CimInstance {{
    param($ClassName,$Filter)
    $global:calls++
    $date=[datetime]'2026-10-17T00:00:00Z'
    if ({reused} -and $global:calls -gt 1) {{ $date=$date.AddSeconds(1) }}
    [pscustomobject]@{{Name='MATLAB.exe'; CommandLine={quote(token)}; CreationDate=$date}}
}}
function global:Stop-Process {{ param($Id,$ErrorAction) $global:stopCalled=$true }}
function global:Start-Sleep {{ param($Seconds) throw 'fixture_poll_complete_without_stop' }}
try {{
    $output=& {quote(SCRIPT)} -RunFolder {quote(run)} -MatlabProcessId 999999 `
        -ExpectedCommandToken 'exact_run_token' -ArchiveReserveGiB 999999 -RunReserveGiB 999999 `
        {'-InspectOnly' if condition == 'inspect' else ''}
    [pscustomobject]@{{StopCalled=$global:stopCalled; Output=($output -join "`n"); Error=''}} | ConvertTo-Json
}} catch {{
    [pscustomobject]@{{StopCalled=$global:stopCalled; Output=''; Error=$_.Exception.Message}} | ConvertTo-Json
}}
"""
    encoded = base64.b64encode(command.encode("utf-16le")).decode("ascii")
    result = subprocess.run([shutil.which("pwsh") or "powershell.exe", "-NoProfile", "-EncodedCommand", encoded],
                            text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr
    record = json.loads(result.stdout)
    assert record["StopCalled"] is (condition == "valid")
    if condition == "valid":
        assert not record["Error"]
        receipt = json.loads(record["Output"])
        assert receipt["CompletedSlot"] == 50 and receipt["NextSlot"] == 51
        assert receipt["StateSHA256"] == digest and not receipt["EvidenceDeleted"]
    elif condition == "inspect":
        assert not record["Error"] and json.loads(record["Output"])["Action"] == "inspect_only_no_stop"
    else:
        assert record["Error"]
    assert hashlib.sha256(state.read_bytes()).hexdigest() == digest
