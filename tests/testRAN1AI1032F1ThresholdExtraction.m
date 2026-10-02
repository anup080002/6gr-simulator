function ok=testRAN1AI1032F1ThresholdExtraction()
% Formula fixture only: no fixture row is written as calibration evidence.
study=sixgr.studies.ran1ai1032.loadStudyConfig();
CaseID=repmat("fixture_H0_AWGN_r1",2,1); EntryID=repmat("H0",2,1);
a=sixgr.studies.ran1ai1032.MCSCatalog.optionA(); a=a(a.entry_id=="H0",:);
ChannelProfile=repmat("AWGN",2,1); DelaySpread_ns=zeros(2,1);
AntennaCaseID=repmat("fixture_4x4",2,1); Rank=ones(2,1);
TxChains=4*ones(2,1); RxChains=TxChains; Qm=10*ones(2,1);
TargetCodeRateX1024=repmat(a.target_code_rate_x1024,2,1);
ConfiguredSNR_dB=[30;30.1]; MeanMeasuredSINR_dB=[24;24.08]; BLER=[.12;.08];
StatisticsComplete=true(2,1); Censored=false(2,1);
TransportBlockCount=3000*ones(2,1); ErrorCount=[360;240];
ExecutionBackend=repmat("canonical_pusch_waveform_chain",2,1);
SourceClassification=repmat("executed_phy_truth",2,1);
RFBranch=repmat("ideal_debug",2,1); PowerPlane=repmat("normalized_total_UE_power_occupied_RE_reference",2,1);
T=table(CaseID,EntryID,ChannelProfile,DelaySpread_ns,AntennaCaseID,Rank,TxChains,RxChains, ...
    Qm,TargetCodeRateX1024,ConfiguredSNR_dB,MeanMeasuredSINR_dB,BLER,StatisticsComplete, ...
    Censored,TransportBlockCount,ErrorCount,ExecutionBackend,SourceClassification,RFBranch,PowerPlane);
T.RFProfileID=repmat("fixture_ideal_not_physical_calibration",height(T),1);
r=sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(T,study);
assert(height(r)==1 && abs(r.RequiredReferenceSNRdB-30.05)<1e-10 && ...
    abs(r.RequiredSINRdB-24.04)<1e-10 && r.ErrorCount==240);
bad=T; bad.Censored(2)=true;
assert(isempty(sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(bad,study)));
bad=T; bad.ExecutionBackend(:)="lut_proxy";
assert(isempty(sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(bad,study)));
bad=T; bad.ConfiguredSNR_dB(2)=31;
assert(isempty(sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(bad,study)));
other=T; other.CaseID(:)="fixture_H0_CDLC_r1"; other.ChannelProfile(:)="CDL-C";
r=sixgr.studies.ran1ai1032.extractF1CalibrationThresholds([T;other],study);
assert(height(r)==2 && numel(unique(r.SourceChannel))==2);
bad=T; bad.RFProfileID(2)="fixture_changed_oscillator";
try
    sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(bad,study);
    error('test:MissingRejection','Different RF models were pooled.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:ran1ai1032:F1MixedPhysicalCase'));
end
ok=true; fprintf('RAN1_AI1032_F1_THRESHOLD_EXTRACTION_PASS\n');
end
