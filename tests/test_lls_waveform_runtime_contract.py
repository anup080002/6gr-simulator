from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    runner_text = (REPO_ROOT / "+sixgr" / "+lls6g" / "+runners" / "runSingle.m").read_text(encoding="utf-8")
    assert 'sixgr.util.structGet(cfg, "run.totalSlots"' in runner_text
    assert 'sixgr.util.structGet(cfg, "run.numTTI"' in runner_text
    assert 'slotDuration_s = max(eps' in runner_text
    assert 'canonicalSlots=%d' in runner_text

    runtime_text = (REPO_ROOT / "+sixgr" / "+truth" / "CoupledTruthRuntime.m").read_text(encoding="utf-8")
    assert 'state.CurrentCanonicalSlot = double(canonicalSlot);' in runtime_text
    assert 'state.CurrentSlot = double(canonicalSlot);' in runtime_text
    assert 'state.CurrentSlotDLAllowed = logical(slotDLAllowed);' in runtime_text
    assert 'state.CurrentSlotULAllowed = logical(slotULAllowed);' in runtime_text
    assert 'state.CurrentSlotDuplexLabel = char(string(slotLabel));' in runtime_text
    assert 'function [allowDL, allowUL, slotLabel] = slotDuplexState(cfg, canonicalSlot)' in runtime_text
    assert 'runState.CurrentCanonicalSlot = double(sixgr.util.structGet(state, "CurrentCanonicalSlot", NaN));' in runtime_text
    assert 'CurrentCanonicalSlot' in runtime_text

    waveform_text = (REPO_ROOT / "+sixgr" / "+truth" / "runWaveformLinkBundle.m").read_text(encoding="utf-8")
    assert 'function [allowDL, allowUL, slotLabel] = localCoupledSlotDuplexState(cfg, canonicalSlot)' in waveform_text
    assert '"Coupled canonical slot prepared: sweep=%d/%d slot=%d/%d duplex=%s allow_dl=%d allow_ul=%d."' in waveform_text


if __name__ == "__main__":
    main()
