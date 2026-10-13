function ok=testRAStageEvidencePublication()
% Pure evidence-routing test: these explicit fixtures are not PHY outcomes.
stageNames=["Msg1";"Msg2";"Msg3";"Msg4";"RRCSetupComplete"];
names={'msg1_prach_detection','msg2_rar_trials','msg3_pusch_trials', ...
    'msg4_contention_resolution'};
available=struct('ra_attempts',table("fixture",'VariableNames',{'RunId'}));
for k=1:4
    available.(names{k})=table(k,false,'VariableNames',{'StageOrdinal','CrcPass'});
end
available.msg1_detected_candidates=available.msg1_prach_detection;
available.msg2_pdcch_candidates=available.msg2_rar_trials;
available.msg2_dci_fields=available.msg2_rar_trials;
available.msg4_dci_fields=available.msg4_contention_resolution;
for received=0:4
    ra=struct('RuntimeStageRows',table(stageNames(1:received),'VariableNames',{'StageName'}), ...
        'ArtifactTables',available);
    prior=max(received-1,0);
    part=sixgr.truth.takeUnpublishedRAStageEvidence(ra,prior,false);
    assert(~isfield(part,'ra_attempts'),'Pending receiver rows must not imply completed access.');
    for k=1:4
        assert(isfield(part,names{k})==(k==received), ...
            'Publish exactly the newly completed stage, not a future/prepared or repeated stage.');
    end
    if received>0
        assert(~part.(names{received}).CrcPass,'A failed observed decode is still a receiver trial.');
    end
    none=sixgr.truth.takeUnpublishedRAStageEvidence(ra,received,false);
    assert(isempty(fieldnames(none)),'Waiting for a later stage must not republish earlier evidence.');
end
ra.RuntimeStageRows=table(stageNames,'VariableNames',{'StageName'});
for prior=0:4
    final=sixgr.truth.takeUnpublishedRAStageEvidence(ra,prior,true);
    assert(isfield(final,'ra_attempts'));
    for k=1:4
        assert(isfield(final,names{k})==(k>prior),'Terminal export must not duplicate live trials.');
    end
end
ra.RuntimeStageRows=ra.RuntimeStageRows(1:2,:);
try
    sixgr.truth.takeUnpublishedRAStageEvidence(ra,3,false);
catch failure
    assert(strcmp(failure.identifier,'sixgr:truth:RAStageEvidenceRegressed'));
    ok=true;
    fprintf('PASS testRAStageEvidencePublication: pending/terminal and failed-trial routing.\n');
    return;
end
error('test:RAStageLossAccepted','Lost receiver stages must be rejected.');
end
