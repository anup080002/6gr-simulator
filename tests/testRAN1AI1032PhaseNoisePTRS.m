function ok=testRAN1AI1032PhaseNoisePTRS(gridPRBs,ranks)
% Paired actual research-Qm PUSCH reception, not an SLS SINR penalty.
if nargin<1, gridPRBs=25; end
if nargin<2, ranks=[1 2 4]; end
study=sixgr.studies.ran1ai1032.loadStudyConfig();
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study); C=plan.CasePlan;
C=C(C.ExperimentID=="F1" & C.ChannelProfile=="AWGN" & ...
    C.AntennaCaseID=="mimo_4x4_r1_r4" & C.EntryID=="H0" & ismember(C.Rank,ranks),:);
study.lls.execution.grid_prbs=gridPRBs;
branches=["pn_off_ptrs_reference","pn7_ptrs_uncompensated","pn7_ptrs_compensated"];
allTrials=table();
for ci=1:height(C)
T=table();
for id=branches
    study.lls.execution.rf_branch=id;
    cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,C(ci,:),40,103277);
    out=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study); row=out.TrialTable;
    assert(row.PTRSRECount>0 && row.PTRSConfiguredEnabled);
    assert(row.PhaseNoiseApplied==(id~="pn_off_ptrs_reference"));
    assert(row.PTRSCPECorrectionApplied==(id=="pn7_ptrs_compensated"));
    row.ComparisonBranch=id; T=[T;row]; %#ok<AGROW>
    fprintf('PN_PTRS_TRIAL PRBs=%d rank=%d branch=%s CRC=%d EVM=%g\n', ...
        gridPRBs,C.Rank(ci),id,row.CRCPass,row.EVM_rms);
end
assert(T.CRCPass(1) && T.BitErrors(1)==0);
assert(numel(unique(T.TBSize_bits))==1 && numel(unique(T.DataRECount))==1);
% Benefit is statistical, not promised for every noise realization/rank.
% Keep the retained rank-one regression as a deterministic benefit check.
if gridPRBs==25 && C.Rank(ci)==1
    assert(T.EVM_rms(3)<T.EVM_rms(2),'Measured PTRS correction must improve the retained paired fixture EVM.');
end
allTrials=[allTrials;T]; %#ok<AGROW>
end
folder=fullfile(pwd,'logs','nr_inspired_phase_noise_20261001'); if ~isfolder(folder), mkdir(folder); end
name="paired_pusch_ptrs_"+string(gridPRBs)+"prb_r"+join(string(ranks),"-")+"_"+ ...
    string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))+".csv";
writetable(allTrials,fullfile(folder,name));
ok=true; fprintf('RAN1_AI1032_PHASE_NOISE_PTRS_PASS statistical_qualification=0\n');
end
