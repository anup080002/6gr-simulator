function ok = testRuntimeStatusSnapshotIntegrity()
%TESTRUNTIMESTATUSSNAPSHOTINTEGRITY Guard one-row measured status exports.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

raw = struct( ...
    "Stage", 'control_gating_streaming', ...
    "CurrentDirection", char(string("")), ...
    "CurrentSlot", 1, ...
    "PBCHAttemptCount", 1, ...
    "ActiveSSBIndices0Based", '[2,3]', ...
    "Notes", 'receiver-causal measured status');
status = sixgr.truth.canonicalizeRuntimeStatusSnapshot(raw);
assert(isstring(status.Stage) && isscalar(status.Stage));
assert(isstring(status.CurrentDirection) && isscalar(status.CurrentDirection));
assert(status.CurrentDirection == "");
assert(status.ActiveSSBIndices0Based == "[2,3]");

T = struct2table(orderfields(status));
assert(height(T) == 1);
assert(double(T.PBCHAttemptCount(1)) == 1);

bad = raw;
bad.PBCHAttemptCount = [1 2];
localMustThrow(@() sixgr.truth.canonicalizeRuntimeStatusSnapshot(bad), ...
    "sixgr:truth:RuntimeStatusFieldNotScalar");

bad = raw;
bad.CurrentDirection = ['DL'; 'UL'];
localMustThrow(@() sixgr.truth.canonicalizeRuntimeStatusSnapshot(bad), ...
    "sixgr:truth:RuntimeStatusFieldNotScalar");

ok = true;
fprintf("[PASS] testRuntimeStatusSnapshotIntegrity\n");
end

function localMustThrow(fcn, identifier)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(identifier), ...
        "Expected %s, received %s: %s", identifier, ME.identifier, ME.message);
end
assert(threw, "Expected typed failure %s.", identifier);
end
