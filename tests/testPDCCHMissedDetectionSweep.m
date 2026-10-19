function ok=testPDCCHMissedDetectionSweep()
setup6GRSimToolkit('Verbose',false);
b=pdcchStrictAnchorResult('WriteArtifacts',true);
T=b.Result.ArtifactTables.pdcch_missed_detection_sweep;
tr=b.Result.ArtifactTables.pdcch_trials;
assert(height(T)==4 && all(T.WaveformTrialCount==3));
assert(all(T.MissedGrantCount+T.DeliveredGrantCount==T.WaveformTrialCount));
assert(all(T.MissedGrantProbability==T.MissedGrantCount./T.WaveformTrialCount));
assert(all(T.AggregationLevel==b.Config.AggregationLevel));
assert(all(T.TxDimensions==1 & T.RxDimensions==1));
assert(all(T.JointOperatingPointCount==7));
assert(all(abs(T.PerPointConfidenceLevel-(1-(1-.95)/7))<eps));
assert(all(T.AlphaSpentThisLook<= (1-.95)/7/3+eps));
assert(~b.Result.StatisticallyQualified && ~b.Result.DetectionSummary.NRConformanceQualified);
assert(all(T.QualificationScope=="awgn_component_not_nr_conformance"));
h1=tr(tr.TrialType=="missed_detection_sweep",:);
noise=tr(ismember(tr.TrialType,["missed_detection_sweep","false_alarm_sweep"]),:);
assert(height(h1)==12 && height(unique(noise(:,{'NoiseSeed','NoiseSubstream'}),'rows'))==height(noise));
assert(all(noise.NoiseGenerator=="Threefry") && numel(unique(noise.NoiseSeed))==1);
assert(all(~h1.GeneratedNoiseSuppliedToReceiver));
for k=1:height(T)
    part=h1(h1.SNRdB==T.SNRdB(k) & h1.DCIFormatTx==T.DCIFormat(k),:);
    success=part.DCICrcPass & part.DCIPayloadMatch & part.GrantValid & part.ControlResourceValidity & ...
        part.SelectedAggregationLevel==part.TxAggregationLevel & ...
        part.SelectedCandidateIndex==part.TxCandidateIndex & part.SelectedCCEIndex==part.TxCCEIndex;
    assert(height(part)==T.WaveformTrialCount(k) && sum(~success)==T.MissedGrantCount(k));
end
% At the frozen clean high-SNR point, genuine decoded intended grants exist.
assert(all(T.DeliveredGrantCount(T.SNRdB==35)==3));
path=fullfile(b.RunFolder,'control','csv','pdcch_missed_detection_sweep.csv');
disk=sixgr.util.csvReadTable(path);
assert(height(disk)==4 && all(disk.MissedGrantCount==T.MissedGrantCount));
png=fullfile(b.RunFolder,'reports','figures','pdcch_missed_grant_probability.png');
info=imfinfo(png); assert(info.Width>100 && info.Height>100);
lineage=sixgr.util.csvReadTable(fullfile(b.RunFolder,'control','csv','pdcch_plot_lineage.csv'));
assert(height(lineage)==8);

raw=b.InternalConfig.phy.pdcch.operatorControl.pdcch_strict;
assert(~sixgr.phy.pdcch.resolveMissedDetectionQualification(rmfield(raw,'missed_detection_qualification')).Enabled);
for k=1:6
    invalid=raw;
    switch k
        case 1, invalid.missed_detection_qualification=rmfield(invalid.missed_detection_qualification,'snr_db');
        case 2, invalid.missed_detection_qualification.channel_model='TDL-C';
        case 3, invalid.missed_detection_qualification.scope='nr_conformance';
        case 4, invalid.missed_detection_qualification.snr_db=[1 1];
        case 5, invalid.missed_detection_qualification.planned_looks=1;
        case 6, invalid.missed_detection_qualification.dci_formats={'1_0','1_0'};
    end
    rejected=false;
    try, sixgr.phy.pdcch.resolveMissedDetectionQualification(invalid); catch cause
        rejected=startsWith(string(cause.identifier),"sixgr:phy:pdcch:");
    end
    assert(rejected,'Invalid qualification context/grid/budget must fail before execution.');
end
changed=b.InternalConfig;
changed.phy.pdcch.operatorControl.pdcch_strict.missed_detection_qualification.snr_db=[-9 35];
same=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(b.InternalConfig, ...
    'RunFolder',b.RunFolder,'RunId',b.Config.RunId,'ScenarioName',b.Config.ScenarioName);
other=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(changed, ...
    'RunFolder',b.RunFolder,'RunId',b.Config.RunId,'ScenarioName',b.Config.ScenarioName);
assert(same.ConfigHash==b.Config.ConfigHash);
assert(other.ConfigHash~=b.Config.ConfigHash,'Frozen H1 grid must participate in the context hash.');
changed=b.InternalConfig;
changed=sixgr.util.structSet(changed,'lls6g.control.pdcch_strict.false_alarm_snr_db',[-7 0 6]);
other=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(changed, ...
    'RunFolder',b.RunFolder,'RunId',b.Config.RunId,'ScenarioName',b.Config.ScenarioName);
assert(other.ConfigHash~=b.Config.ConfigHash && isequal(other.StatisticalQualification.FalseAlarmSNRdB,[-7 0 6]), ...
    'Frozen H0 grid must also participate in the context hash.');
ok=true;
fprintf('PDCCH_MISSED_DETECTION_SWEEP_PASS physical_H1_trials=%d paired_noise_unique=1 artifact_root=%s\n',height(h1),b.RunFolder);
end
