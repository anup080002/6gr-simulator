function ok = testSIB1ValidationComparisonContract()
%TESTSIB1VALIDATIONCOMPARISONCONTRACT Guard fail-closed SIB1 artifacts.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
tree = struct("asn1Release", "3GPP_TS_38_331_V18_9_0", ...
    "profile", "bounded_test", ...
    "message", struct("cellIdentity", 17, "tac", 3));
payloadHash = sixgr.util.sha256Hex(uint8([1 2 3 4]));
tx = struct("TxTree", tree, "SIB1PayloadHash", payloadHash);
rx = struct("StrictOk", true, "Status", "PASS", ...
    "FailureReason", "", "SIB1ASN1DecodeOk", true, ...
    "SIB1RxTree", tree, "SIB1PayloadHashRx", payloadHash);

matched = sixgr.phy.broadcast.attachSIB1ValidationComparison(tx, rx);
assert(logical(matched.StrictOk) && logical(matched.SIB1TreeEqual));
assert(strlength(string(matched.SIB1TxTreeHash)) == 64 && ...
    string(matched.SIB1TxTreeHash) == string(matched.SIB1RxTreeHash));
assert(string(matched.Status) == "PASS" && ...
    strlength(string(matched.FailureReason)) == 0);

mismatched = rx;
mismatched.SIB1RxTree.message.cellIdentity = 18;
mismatched = sixgr.phy.broadcast.attachSIB1ValidationComparison(tx, mismatched);
assert(~logical(mismatched.StrictOk) && ...
    ~logical(mismatched.SIB1TreeEqual));
assert(string(mismatched.FailureReason) == "sib1_decoded_tree_mismatch");

missing = rmfield(tx, "TxTree");
missingResult = sixgr.phy.broadcast.attachSIB1ValidationComparison(missing, rx);
assert(~logical(missingResult.StrictOk));
assert(string(missingResult.FailureReason) == ...
    "sib1_transmit_tree_missing_for_semantic_comparison");

ok = true;
end
