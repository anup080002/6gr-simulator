function ok=testMeasuredSINRCRCAccounting()
% Declared export fixtures: unknown CRC is neither a pass nor a failure.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
base=table(repmat("DL",6,1),(1:6).',repmat(20,6,1), ...
    repmat("OK",6,1),true(6,1),false(6,1),false(6,1), ...
    [1;0;NaN;Inf;-1;2],repmat(1000,6,1),repmat(1000,6,1), ...
    repmat(1000,6,1),zeros(6,1),repmat(1,6,1),repmat(100,6,1), ...
    'VariableNames',{'Direction','Slot','PostEqSINR_dB', ...
    'PostEqSINRValueStatus','FinalizedFlag','IsWarmupFrame','FallbackFlag', ...
    'CRCPass','TBSize_bits','OfferedBits','BitsCompared','BitErrors', ...
    'Throughput_Mbps','PropagationDistance_m'});
for caseIndex=1:5
    T=base; expectedKnown=2; expectedUnknown=4; expectedBLER=.5;
    if caseIndex==2
        T.CRCPass=["true";"failed";"not_decoded";"NaN";"";"2"];
    elseif caseIndex==3
        T=removevars(T,'CRCPass'); T.Status=repmat("PASS",6,1);
        expectedKnown=0; expectedUnknown=6; expectedBLER=NaN;
    elseif caseIndex==4
        T.CRCPass(:)=NaN; T.TBCrcPass=ones(6,1);
        expectedKnown=0; expectedUnknown=6; expectedBLER=NaN;
    elseif caseIndex==5
        T.TBCrcPass=T.CRCPass; T=removevars(T,'CRCPass');
    end
    root=tempname; mkdir(root);
    cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
    out=sixgr.analytics.generateMeasuredSINRCurves(root,'crc_accounting', ...
        'TrialData',struct('dl',T,'ul',table()), ...
        'ScenarioConfig',struct('global_radio_scope', ...
        struct('channel_bandwidth_hz',5e6)), ...
        'WriteKPISummary',true,'UpdateAnchorKPIs',false);
    S=out.Tables.Summary; K=out.Tables.KPISummary; B=out.Tables.DLBlerCurve;
    assert(isequaln(S.BLER_overall,expectedBLER), ...
        'test:UnknownCRCCountedAsPass','Unknown CRC changed the observed BLER denominator.');
    assert(S.N_Trials==6 && S.CRCObservedTrialCount==expectedKnown && ...
        S.CRCUnknownTrialCount==expectedUnknown);
    assert(isequaln(K.BLER_overall,expectedBLER) && ~K.StrictOk);
    assert(K.CRCUnknownTrialCount==expectedUnknown && isnan(K.Goodput_Mbps), ...
        'No delivered-bit observation may be fabricated from an unknown CRC.');
    assert(~out.Tables.BlerBerReconciliation.BlerBerReconciliationOk);
    if expectedKnown==0
        assert(isempty(B),'No BLER point exists without a CRC observation.');
    else
        assert(height(B)==1 && B.TrialCount==expectedKnown && ...
            B.FailureCount==1 && B.CRCUnknownTrialCount==expectedUnknown);
        assert(B.BLER_CI_Low<.5 && B.BLER_CI_High>.5);
    end
    assert(nnz(isnan(out.Tables.DistanceScatter.CRCPass))==expectedUnknown);
    persisted=readtable(out.Paths.DLBlerCurve,'VariableNamingRule','preserve');
    assert(height(persisted)==height(B));
    fprintf('MEASURED_SINR_CRC_ACCOUNTING_PASS case=%d known=%d unknown=%d\n', ...
        caseIndex,expectedKnown,expectedUnknown);
    clear cleanup;
end
ok=true;
end
