function ok=testRAN1AI1032F1PhysicalSmoke(gridPRBs,ranks,includeNegative)
% One full-band physical TB by default; this is not statistical qualification.
if nargin<1, gridPRBs=273; end
if nargin<2, ranks=1; end
if nargin<3, includeNegative=false; end
study=sixgr.studies.ran1ai1032.loadStudyConfig();
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study);
study.lls.execution.grid_prbs=gridPRBs; % Explicit focused-test allocation override only.
C=plan.CasePlan;
C=C(C.ExperimentID=="F1" & C.ChannelProfile=="AWGN" & ...
    C.AntennaCaseID=="mimo_4x4_r1_r4" & C.EntryID=="H0" & ismember(C.Rank,ranks),:);
power=zeros(height(C),1);
for i=1:height(C)
    cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C(i,:),40,103222);
    r=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study);
    T=r.TrialTable;
    assert(height(T)==1 && T.CRCPass && T.BitErrors==0);
    assert(T.ChannelEstimateAvailable && T.EqualizationAvailable);
    assert(T.NumRxAntennas==4 && T.NumTxPorts==4 && T.Layers==C.Rank(i));
    assert(abs(T.AppliedAWGNSNR_dB-40)<1e-10 && T.TBSize_bits==T.BitsCompared);
    assert(T.MeasuredTrialSINRSource~="configured_snr");
    power(i)=T.PowerNormalizationGridMeanEnergyPerRE;
end
assert(max(power)-min(power)<1e-10 && ...
    all(abs(power-study.lls.execution.normalized_total_ue_grid_re_energy)<1e-10));
if includeNegative
    cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C(1,:),-10,103222);
    negative=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study);
    assert(~negative.TrialTable.CRCPass && negative.TrialTable.BitErrors>0 && ...
        negative.TrialTable.MeasuredSINR_dB<T.MeasuredSINR_dB);
end
ok=true; fprintf('RAN1_AI1032_F1_PHYSICAL_SMOKE_PASS PRBs=%d primary_calibration_evidence=0\n',gridPRBs);
end
