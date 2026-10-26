function ok=testDataCRCOutcomeEvidence()
% Explicit decoder/publication fixtures, not new physical observations.
T=table([1;1;1;0;NaN],[1;0;NaN;NaN;NaN],[1;1;0;0;0], ...
    strings(5,1),'VariableNames',{'CRCApplicable','CRCPass','DecodeAttempted','CRCOutcome'});
original=T(:,1:3); actual=sixgr.truth.bindDataCRCOutcome(T);
assert(isequaln(actual(:,1:3),original)&& ...
    isequal(actual.CRCOutcome,["pass";"fail";"unavailable";"not_applicable";"unavailable"]));
assert(isequaln(sixgr.truth.bindDataCRCOutcome(actual),actual));
% Original decoder applicability, unknown CRCs and their labels survive both
% public data projections. Publication cannot turn an unknown CRC into NACK.
meta=struct('logical_run_id',"declared_CRC_projection_fixture",'run_id',NaN);
for pair={"pdsch","pusch"}
    channel=string(pair{1}); base=struct(); base.(channel+"_table")=actual;
    published=sixgr.truth.buildLLSPublicOutputTables(base,sixgr.truth.llsOutputContract(),meta);
    public=published.(channel+"_runtime_event_table");
    for name=["CRCApplicable","CRCPass","CRCOutcome"]
        assert(isequaln(public.(name),actual.(name)), ...
            'Public %s projection changed original %s.',channel,name);
    end
end
bad=T; bad.CRCOutcome(2)="pass"; reject(bad,'sixgr:truth:DataCRCConflict');
bad=T; bad.DecodeAttempted(1)=0; reject(bad,'sixgr:truth:DataCRCWithoutDecode');
bad=T; bad.CRCPass(1)=2; reject(bad,'sixgr:truth:DataCRCValue');
ok=true;
end
function reject(T,identifier)
try, sixgr.truth.bindDataCRCOutcome(T); catch cause
    assert(strcmp(cause.identifier,identifier),'%s',cause.message); return;
end
error('testDataCRCOutcomeEvidence:MissingGuard','Expected rejection %s.',identifier);
end
