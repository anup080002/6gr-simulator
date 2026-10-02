function ok=testRAN1AI1032F1RFExecution(gridPRBs)
%TESTRAN1AI1032F1RFEXECUTION RF branches must reach the actual PUSCH decoder.
% Reduced PRBs are a dedicated integration fixture, not campaign evidence.
if nargin<1, gridPRBs=25; end
study=sixgr.studies.ran1ai1032.loadStudyConfig();
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study);
C=plan.CasePlan;
C=C(C.ExperimentID=="F1" & C.ChannelProfile=="AWGN" & ...
    C.AntennaCaseID=="mimo_4x4_r1_r4" & C.EntryID=="H0" & C.Rank==1,:);
study.lls.execution.grid_prbs=gridPRBs;
study.lls.execution.rf_branch='ideal_debug';
cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C,40,103222);
baseline=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study);
ideal=baseline.TrialTable;
assert(ideal.CRCPass && ideal.BitErrors==0 && ~ideal.PowerCapActive);
b=struct('id',"rf_decoder_fixture",'modulation',"1024QAM", ...
    'tx_evm_percent',2.8,'rx_evm_percent',2.3, ...
    'residual_normalized_cfo',0,'requested_tx_power_dbm',31, ...
    'power_class_max_dbm',31,'mpr_db',0,'phase_noise_enabled',false, ...
    'power_plane',"normalized_reference_relative_cap", ...
    'classification',"6GR_explicit_study_assumption");
evm=run(b);
assert(abs(evm.MeasuredTXEVMPercent-2.8)<0.14 && ...
    abs(evm.MeasuredRXEVMPercent-2.3)<0.12);
assert(evm.RXEVMReferenceSource=="actual_physical_sum_before_receiver_noise");
assert(evm.MeasuredSINR_dB<ideal.MeasuredSINR_dB);
b.tx_evm_percent=0; b.rx_evm_percent=0; b.mpr_db=8;
cap=run(b);
assert(cap.PowerCapActive && abs(cap.MeasuredTransmitPowerRatio-10^(-8/10))<1e-10);
assert(cap.ConfiguredAppliedPowerdBm==23 && isnan(cap.ActualTotalTxPower_dBm));
assert(cap.AppliedGridNoiseVariance==ideal.AppliedGridNoiseVariance && ...
    cap.AppliedAWGNSNR_dB==ideal.AppliedAWGNSNR_dB, ...
    'MPR must attenuate transmitted samples without moving the pre-cap noise reference.');
assert(cap.MeasuredSINR_dB<ideal.MeasuredSINR_dB);
b.mpr_db=0; b.residual_normalized_cfo=0.01;
cfo=run(b);
assert(abs(cfo.AppliedCFOHz-0.01*study.carrier.scs_khz*1000)<1e-10);
folder=fullfile(pwd,'results','ai_10_3_2_modulation','focused_20261001');
if ~isfolder(folder), mkdir(folder); end
rfTrials=[ideal;evm;cap;cfo];
rfTrials.QualificationBranch=["ideal";"additive_EVM";"MPR_8dB";"CFO_0p01"];
rfTrials.QualificationGridPRBs=repmat(gridPRBs,height(rfTrials),1);
rfTrials.StatisticalQualification=false(height(rfTrials),1);
writetable(rfTrials,fullfile(folder,"rf_decoded_"+string(gridPRBs)+"prb.csv"));
b.phase_noise_enabled=true;
study.rf.waveform_branches={b};
try
    sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C,40,103222);
    error('test:ExpectedFailure','Missing phase-noise profile was accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:ran1ai1032:F1PhaseNoiseMask'));
end
ok=true;
fprintf('RAN1_AI1032_F1_RF_EXECUTION_PASS PRBs=%d statistical_qualification=0\n',gridPRBs);

    function T=run(branch)
        study.rf.waveform_branches={branch};
        study.lls.execution.rf_branch=branch.id;
        c=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C,40,103222);
        result=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(c,study);
        T=result.TrialTable;
        assert(T.ChannelEstimateAvailable && T.EqualizationAvailable && ...
            T.BitsCompared==T.TBSize_bits && T.TBSize_bits==ideal.TBSize_bits);
        assert(T.MeasuredTrialSINRSource~="configured_snr" && ...
            T.NominalPreCapGridReferenceEnergy==ideal.NominalPreCapGridReferenceEnergy);
    end
end
