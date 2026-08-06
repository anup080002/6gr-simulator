function result = attachSIB1ValidationComparison(tx, result)
%ATTACHSIB1VALIDATIONCOMPARISON Bind decoded SIB1 to transmitted semantics.
%
% This is a validation-harness boundary, not receiver oracle input.  It is
% called only after waveform recovery has completed and compares the
% independently decoded payload/tree with the transmitted payload/tree.
% Missing comparison evidence fails closed so an artifact cannot claim
% StrictOk while TreeEqual is false or unevaluated.

txTree = sixgr.util.structGet(tx, "TxTree", struct());
rxTree = sixgr.util.structGet(result, "SIB1RxTree", struct());
decoded = logical(sixgr.util.structGet(result, "SIB1ASN1DecodeOk", false));
txPayloadHash = string(sixgr.util.structGet(tx, "SIB1PayloadHash", ""));
rxPayloadHash = string(sixgr.util.structGet(result, "SIB1PayloadHashRx", ""));

result.SIB1PayloadHashTx = txPayloadHash;
result.SIB1TxTreeHash = "";
result.SIB1TreeEqual = false;

if ~decoded
    result = localFail(result, "sib1_asn1_decode_not_available_for_semantic_comparison");
    return;
end
if ~(isstruct(txTree) && isscalar(txTree) && ~isempty(fieldnames(txTree)))
    result = localFail(result, "sib1_transmit_tree_missing_for_semantic_comparison");
    return;
end
if ~(isstruct(rxTree) && isscalar(rxTree) && ~isempty(fieldnames(rxTree)))
    result = localFail(result, "sib1_receive_tree_missing_for_semantic_comparison");
    return;
end
if strlength(strtrim(txPayloadHash)) == 0 || ...
        strlength(strtrim(rxPayloadHash)) == 0
    result = localFail(result, "sib1_payload_hash_missing_for_semantic_comparison");
    return;
end

[treeEqual, hashes] = sixgr.rrc.asn1.compareSIB1Trees(txTree, rxTree);
payloadEqual = strcmpi(txPayloadHash, rxPayloadHash);
result.SIB1TxTreeHash = string(hashes.TxTreeHash);
result.SIB1RxTreeHash = string(hashes.RxTreeHash);
result.SIB1TreeEqual = logical(treeEqual);
result.StrictOk = logical(sixgr.util.structGet(result, "StrictOk", false)) && ...
    logical(treeEqual) && logical(payloadEqual);
if result.StrictOk
    result.Status = "PASS";
    result.FailureReason = "";
elseif ~treeEqual
    result = localFail(result, "sib1_decoded_tree_mismatch");
elseif ~payloadEqual
    result = localFail(result, "sib1_decoded_payload_hash_mismatch");
else
    result = localFail(result, "sib1_receiver_strict_conditions_failed");
end
end

function result = localFail(result, reason)
result.StrictOk = false;
result.Status = "FAIL";
result.FailureReason = string(reason);
end
