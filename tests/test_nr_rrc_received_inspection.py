"""Draft byte/parser tests only: no PHY/RF or original artifact mutation."""
import hashlib
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("received_codec_draft", Path(__file__).resolve().parents[1] / "tools" / "initial_access" / "nr_rrc_access_codec.py")
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)


def original_request():
    return codec.execute("encode", {"message_kind": "setup_request", "semantic": {
        "identity_type": "randomValue", "identity_value": 2**38 + 7,
        "establishment_cause": "mo-Signalling"}})


def inspect(wire):
    return codec.execute("inspect_received", {"message_kind": "setup_request", "uper_hex": wire.hex().upper()})


def test_original_accepted_octets():
    message = original_request()
    wire = bytes.fromhex(message["uper_hex"])
    result = inspect(wire)
    assert result["accepted"] and result["decoded"] == message
    assert result["uper_hex"] == wire.hex().upper()
    assert result["sha256"] == hashlib.sha256(wire).hexdigest()
    assert not result["physical_reception_proved"]


def test_truncated_native_bits():
    wire = bytes.fromhex(original_request()["uper_hex"])[:2]
    result = inspect(wire)
    assert not result["accepted"] and result["status"] == "received_UPER_decode_rejected"
    assert result["sha256"] == hashlib.sha256(wire).hexdigest()


def test_trailing_original_bytes_not_silently_ignored():
    wire = bytes.fromhex(original_request()["uper_hex"]) + b"\x00"
    result = inspect(wire)
    assert not result["accepted"] and result["status"] == "received_noncanonical_or_trailing_octets"
    with pytest.raises(ValueError):
        codec.execute("decode", {"message_kind": "setup_request", "uper_hex": wire.hex()})


def test_other_legal_message_choice_remains_outside_profile():
    # UL-CCCH messageClassExtension root choice, not a forged accepted request.
    wire = codec.M.UL_CCCH_Message.to_uper({"message": ("messageClassExtension", {})})
    result = inspect(wire)
    assert not result["accepted"] and result["status"] == "received_message_outside_supported_profile"


@pytest.mark.parametrize("kind", ["security_mode_command", "reconfiguration"])
def test_wrong_api_kind_is_not_receive_rejection(kind):
    with pytest.raises(KeyError):
        codec.execute("inspect_received", {"message_kind": kind + "_unknown", "uper_hex": "00"})


@pytest.mark.parametrize("error", [RuntimeError("internal failure"), ValueError("unexpected implementation bug"), KeyError("missing implementation field")])
def test_unexpected_implementation_fault_propagates(monkeypatch, error):
    wire = bytes.fromhex(original_request()["uper_hex"])
    def fail(*_):
        raise error
    monkeypatch.setattr(codec, "semantic_for", fail)
    with pytest.raises(type(error), match="internal failure|unexpected implementation bug|missing implementation field"):
        inspect(wire)


def test_strict_encoder_is_not_downgraded_to_rejection_status():
    with pytest.raises(ValueError):
        codec.execute("encode", {"message_kind": "setup_request", "semantic": {
            "identity_type": "randomValue", "identity_value": -1,
            "establishment_cause": "mo-Signalling"}})
