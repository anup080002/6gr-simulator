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

% Exercise the production publication boundary, not a hardcoded stage flag.
folder=tempname; layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU> owned temporary test folder
file=fullfile(layout.AirInterfaceCSVDir,'link_anchor_kpis.csv');
anchor=table("fixture_executed_anchor","FAIL", ...
    'VariableNames',{'Case','Status'});
for population=0:2
    if population==1
        sixgr.util.csvWriteTable(file,anchor([],:),'PreserveSchema',true);
    elseif population==2
        sixgr.util.csvWriteTable(file,anchor);
    end
    for stage=["link_anchor_complete","control_gating_streaming","dl_raw_trials_ready", ...
            "harq_ready","final_bundle_ready"]
        raw.Stage=stage; raw.AnchorKPIsReady=true; % Poison earlier caller's assumption.
        status=sixgr.truth.canonicalizeRuntimeStatusSnapshot(raw,folder);
        assert(status.AnchorKPIsReady==(population==2) && ...
            status.AnchorKPIRowCount==double(population==2));
        assert(status.AnchorKPIEvidenceSource=="air_interface/csv/link_anchor_kpis.csv");
        if population==2
            assert(status.AnchorKPIAvailabilityStatus=="published_rows_not_qualification");
        end
        assert(height(struct2table(orderfields(status)))==1);
    end
end
% A persisted zero-row replacement must not inherit a stale previous true.
sixgr.util.csvWriteTable(file,anchor([],:),'PreserveSchema',true);
status=sixgr.truth.canonicalizeRuntimeStatusSnapshot(status,folder);
assert(~status.AnchorKPIsReady);

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
