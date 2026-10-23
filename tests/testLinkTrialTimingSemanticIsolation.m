function ok=testLinkTrialTimingSemanticIsolation()
% Run the exact production table adapter, with no PHY or scenario launch.
% Timing fields below are labelled negative/unit fixtures, not observations.
setup6GRSimToolkit('Verbose',false);
% Exercise the single production owner directly, not a copied local body.
normalize=@(row,direction,cfg)sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable( ...
    row,direction,40,cfg);
cfg=sixgr.config.defaultConfig();
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
row=table([11;-3],[7;23],[4;15],nan(2,1),nan(2,1),nan(2,1),[false;true], ...
    'VariableNames',{'TrueTimingOffset_samples','TimingOffset_samples', ...
    'TimingError_samples','InjectedTimingOffset_samples','AppliedTimingCorrection_samples', ...
    'ResidualTimingError_PostCorrection_samples','TimingEstimateUsed'});
for direction=["DL","UL"]
    before=rng;
    normalized=normalize(row,direction,cfg);
    assert(isequal(rng,before),'Table normalization must not execute a new realization.');
    assert(isequaln(normalized(:,row.Properties.VariableNames),row), ...
        'test:TimingPlanesConflated', ...
        'Arrival truth, an estimate and its scoring error do not supply injection, application or a post-correction residual.');
    % Distinct explicit producer values, including a true applied zero,
    % must survive unchanged, without being overwritten by other aliases.
    measured=row;
    measured.InjectedTimingOffset_samples=[1;2];
    measured.AppliedTimingCorrection_samples=[0;25];
    measured.ResidualTimingError_PostCorrection_samples=[.25;-.5];
    normalized=normalize(measured,direction,cfg);
    assert(isequaln(normalized(:,measured.Properties.VariableNames),measured));
    % Ordinary scheduled allocations are not feedback scheduling events.
    % Exercise the actual production adapter, including its default schema.
    grants=table([1;2;3],[0;12;25],[false;false;true], ...
        ["fixed_configuration";"frozen_PHYGrant";"received_CSI"], ...
        repmat("frozen_PHYGrant",3,1), ...
        'VariableNames',{'Slot','MCSIndex','LinkAdaptationScheduled', ...
        'MCSAuthority','GrantOperatingPointSource'});
    normalized=normalize(grants,direction,cfg);
    assert(isequal(normalized.LinkAdaptationScheduled,grants.LinkAdaptationScheduled), ...
        'test:InventedAdaptationDecision','Finite MCS/grant metadata cannot manufacture feedback decisions.');
    grants.LinkAdaptationApplied=[false;false;true];
    grants.AppliedLinkAdaptationResolvedCQI=[10;12;13];
    grants.LinkAdaptationAppliedFeedbackSourceSlot=[NaN;1;2];
    normalized=normalize(grants,direction,cfg);
    assert(isequal(normalized.LinkAdaptationApplied,grants.LinkAdaptationApplied), ...
        'test:InventedAdaptationApplication','Finite CQI/source metadata cannot override the producer application flag.');
end
fprintf('LINK_TRIAL_TIMING_SEMANTIC_ISOLATION_PASS DL_UL=1 adaptation_event_flags_preserved=1 physical_qualification=0\n');
ok=true;
end
