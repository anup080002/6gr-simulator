function ok = testAdaptiveOperatingPointTrialAuthority()
% Actual isolated DL/UL coding: pre-TB authority, not adaptive qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=sixgr.config.defaultConfig();
cfg=withCanonicalSchedulerTiming(cfg);
cfg.run.shortRun=true;
cfg.run.noiseOperatingMode="standalone_awgn_snr_argument";
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
cfg.lls6g.userContext.UEIndex=2;
cfg.phy.pdsch.RNTI=181; cfg.phy.pusch.RNTI=182;
cfg.phy.linkAdaptation.mode="amc";
cfg.phy.linkAdaptation.dlPolicy="baseline";
cfg.phy.linkAdaptation.ulPolicy="baseline";
cfg.phy.linkAdaptation.rankPolicy="fixed";
cfg.phy.linkAdaptation.beamPolicy="fixed";
cfg.phy.linkAdaptation.initialMCSIndex=1;
cfg.phy.linkAdaptation.maximumMCSIndex=28;
cfg.phy.linkAdaptation.feedbackDelaySlots=1;
cfg.phy.csi.feedbackDelaySlots=1;
folder=fullfile(pwd,'results','lls','adaptive_trial_authority', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
save(fullfile(folder,'configuration.mat'),'cfg');
fprintf('ADAPTIVE_AUTHORITY_EVIDENCE=%s\n',folder);
for direction=["DL","UL"]
    if direction=="DL"
        result=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',3,'SNR_dB',18, ...
            'ExecutionProfile','phy_calibration');
    else
        result=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',3,'SNR_dB',18);
    end
    T=result.TrialTable;
    writetable(T,fullfile(folder,lower(direction)+'_trials.csv'));
    assert(~result.Skipped && height(T)==3,'test:AdaptiveTrialsMissing','Expected three actual trials.');
    assert(all(~T.Crash) && all(ismember(T.HARQCurrentDecodeOK,[0 1])) && ...
        isequal(double(T.HARQCombinedDecodeOK),double(T.CRCPass)), ...
        'test:HARQTrialOutcomeLost','Every actual %s decode must retain its own receiver outcome.',direction);
    assert(T.HARQCurrentDecodeOK(end)==double(result.HARQ.CurrentDecodeOK) && ...
        T.HARQCombinedDecodeOK(end)==double(result.HARQ.CombinedDecodeOK) && ...
        all(T.HARQCombiningApplied==0), ...
        'test:HARQTrialStateMismatch','Independent attempts must retain actual non-combined outcomes.');
    bootstrap=string(T.ActualMCSSelectionMode)=="configured_initial_mcs";
    assert(bootstrap(1) && ~T.LinkAdaptationApplied(1) && T.MCS(1)==1);
    for field=["MCSSelectionSource","MCSAuthority","ModulationAuthority","AppliedOperatingPointSource"]
        assert(all(string(T.(field)(bootstrap))=="configured_initial_mcs"), ...
            'test:BootstrapAuthorityLost','%s %s does not retain bootstrap ownership.',direction,field);
    end
    applied=logical(T.LinkAdaptationApplied);
    assert(any(applied),'test:NoAppliedAdaptiveDecision','Expected delayed feedback to be exercised.');
    assert(all(T.LinkAdaptationAppliedFeedbackSourceSlot(applied)<T.Slot(applied)) && ...
        all(T.AppliedLinkAdaptationMCS(applied)==T.MCS(applied)), ...
        'test:AppliedAuthorityMismatch','Operating point must match earlier applied feedback.');
    fprintf('%s bootstrap=%d applied=%d; real coded attempts=%d\n', ...
        direction,nnz(bootstrap),nnz(applied),height(T));
end
ok=true;
end
