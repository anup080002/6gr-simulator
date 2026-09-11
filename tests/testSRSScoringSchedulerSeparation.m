function ok=testSRSScoringSchedulerSeparation
% Deliberate scheduler fixtures, not measured PHY or exported trial evidence.
setup6GRSimToolkit('Verbose',false);
for mode=["TDD","FDD"]
    file='lls_causal_access_to_data_wiring_tdd.yaml';
    if mode=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),6);
    state.CurrentSlot=5; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
    row=struct2table(struct('Slot',5,'Frame',1,'Status',"FAIL",'StrictOk',false, ...
        'DetectionAttempted',true,'DetectionSuccess',true,'ResourceExtractionAttempted',true, ...
        'ResourceExtractionAvailable',true,'ChannelEstimateAttempted',true, ...
        'SRSChannelEstimateAvailable',true,'SRSRuntimeEvidenceUsable',true, ...
        'RIEstimate',1,'NMSE_dB',NaN,'TrueChannelNMSE_dB',NaN));
    for nmse=[NaN -Inf 20]
        row.NMSE_dB=nmse; row.TrueChannelNMSE_dB=nmse;
        got=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,row);
        assert(got.SRSValidityState(1)=="valid");
    end
    for field=["DetectionSuccess","ResourceExtractionAvailable", ...
            "SRSChannelEstimateAvailable","SRSRuntimeEvidenceUsable"]
        bad=row; bad.(field)=false; bad.Status="PASS"; bad.StrictOk=true;
        bad.DetectionUsable=true; bad.SRSResourceExtractionAvailable=true;
        bad.ChannelEstimateAvailable=true; bad.MeasurementUsable=true; bad.StrictReceiverEvidenceOk=true;
        rejected=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,bad);
        assert(rejected.SRSValidityState(1)=="invalid", ...
            'Scoring PASS or a legacy alias overrode canonical %s=false.',field);
        for invalid=[NaN 2]
            bad.(field)=invalid;
            rejected=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,bad);
            assert(rejected.SRSValidityState(1)=="invalid",'Invalid %s was cast to true.',field);
        end
    end
end
fprintf('SRS_SCORING_SCHEDULER_SEPARATION_PASS: TDD/FDD, canonical receiver flags, qualification independence.\n');
ok=true;
end
