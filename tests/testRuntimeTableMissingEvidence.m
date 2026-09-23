function ok=testRuntimeTableMissingEvidence()
% Metadata-only regression through the runtime's real compatible-table merge.
% Declared fixtures are never exported as physical observations.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cases={NaN,true; true,NaN; [NaN;0;1],false; false,[NaN;0;1]; ...
    single(NaN),true; true,single(NaN); 0,true; false,1; ...
    2,true; false,-2; Inf,false; true,-Inf; int16(2),false};
for k=1:size(cases,1)
    a=cases{k,1}; b=cases{k,2};
    state=struct('CurrentSlot',34,'CurrentFrame',4);
    for values={a,b}
        info=struct('SchedulerClass',"declared_metadata_fixture", ...
            'CandidateTable',table(values{1},'VariableNames',{'Evidence'}));
        state=sixgr.truth.CoupledTruthRuntime.recordSchedulerDecisionRuntime(state,info,'DL',1);
    end
    actual=state.SchedulerDecisionTable.Evidence;
    assert(isequaln(double(actual),[double(a);double(b)]), ...
        'test:RuntimeTableEvidenceChanged', ...
        'Mixed numeric/logical evidence must preserve unavailable and nonbinary values (case %d).',k);
end
fprintf('RUNTIME_TABLE_MISSING_EVIDENCE_PASS cases=%d physical_trials=0\n',size(cases,1));
ok=true;
end
