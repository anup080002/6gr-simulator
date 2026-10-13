function ok=testTRSPersistedReceiverEvidence()
% Recorded per-receiver evidence survives canonicalization without a runtime.
raw=table([1;2],[1;1],[9;10],[251;-73],[2;9], ...
    [true;false],[true;true],[true;true],["PASS";"FAIL"], ...
    ["recorded_ue1_tracking";"recorded_ue2_tracking"], ...
    'VariableNames',{'UEIndex','ServingCell','Slot','TRSEstimatedCFO_Hz', ...
    'TRSTimingEstimate_samples','TRSProcessed','TRSCFOEstimateAvailable', ...
    'TRSTimingEstimateAvailable','Status','TRSStateSource'});
actual=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("TRS",raw);
assert(isequaln(actual(:,raw.Properties.VariableNames),raw), ...
    'Persisted tracking values and receiver identity must not be rewritten.');
again=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("TRS",actual);
assert(isequaln(again,actual),'Persisted TRS canonicalization must be idempotent.');

% A measurement-only row does not establish a runtime tracking update.
raw=table(3,40,"PASS",'VariableNames',{'Slot','EstimatedCFO_Hz','Status'});
actual=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("TRS",raw);
assert(height(actual)==1 && actual.EstimatedCFO_Hz==40);
for name=["UEIndex","TRSProcessed","TRSTrackingUpdateTime_s"]
    if ismember(name,string(actual.Properties.VariableNames))
        value=double(actual.(name));
        assert(all(isnan(value) | value==0), ...
            'Missing live tracking evidence must not be manufactured: %s.',name);
    end
end
ok=true;
disp('TRS_PERSISTED_RECEIVER_EVIDENCE_PASS');
end
