function ok=testPUCCHDetectionYAMLAuthority(outputRoot)
% Replay every retained input, no resampling or cherry-picked detector cases.
if nargin<1, outputRoot=tempname; end
setup6GRSimToolkit('Verbose',false);
if ~isfolder(outputRoot), mkdir(outputRoot); end
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
policy=cfg.phy.pucch.receiverDetectionThresholds;
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,int8(1));
[threshold,source]=sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment,policy);
assert(threshold==s.Data.pucch.detection_threshold_format0_two_symbols && threshold==.42);
assert(source=="yaml.pucch.detection_threshold_format0_two_symbols");
resource=f.Assignment.Resource.Data; resource.NumSymbols=1; resource.StartSymbol=13;
oneSymbol=sixgr.phy.pucch.PUCCHTransmissionAssignment(f.Assignment.Data, ...
    sixgr.phy.pucch.PUCCHResource(resource),f.Assignment.PowerControlState,f.Assignment.SpatialRelationState);
assert(sixgr.phy.pucch.resolveDetectionThreshold(oneSymbol,policy)==.49);
for format=1:4
    other=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
    value=sixgr.phy.pucch.resolveDetectionThreshold(other.Assignment,policy);
    assert(value==s.Data.pucch.("detection_threshold_format"+format));
end
changed=s.Data;
changed.pucch.detection_threshold_format0_two_symbols=.61;
sixgr.lls6g.config.validateScenarioConfig(changed,'Kind','scenario','AllowPartial',false);
overrideCfg=sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(changed),tempname);
assert(sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment, ...
    overrideCfg.phy.pucch.receiverDetectionThresholds)==.61);
bad=policy; bad.detection_threshold_format0_two_symbols=NaN;
localReject(@()sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment,bad), ...
    'sixgr:phy:pucch:InvalidDetectionThreshold');
bad=rmfield(policy,'detection_threshold_format0_two_symbols');
localReject(@()sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment,bad), ...
    'sixgr:phy:pucch:MissingDetectionThreshold');
localReject(@()sixgr.link.runPUCCHWaveformTrial(cfg,'Assignment',f.Assignment, ...
    'Report',f.Report,'PrepareOnly',true,'DetectionThreshold',.1), ...
    'sixgr:link:PUCCHDetectionYAMLAuthorityRequired');
missing=cfg;
missing.phy.pucch=rmfield(missing.phy.pucch,'receiverDetectionThresholds');
localReject(@()sixgr.link.runPUCCHWaveformTrial(missing,'Assignment',f.Assignment, ...
    'Report',f.Report,'PrepareOnly',true), ...
    'sixgr:link:PUCCHDetectionYAMLAuthorityRequired');
partial=struct('pucch',struct('detection_threshold_format0_two_symbols',1.1));
rejected=false;
try, sixgr.lls6g.config.validateScenarioConfig(partial,'Kind','scenario','AllowPartial',true);
catch cause
    rejected=contains(string(cause.message),'detection_threshold_format0_two_symbols');
end
assert(rejected,'Schema must reject an out-of-range detector threshold.');
inputRoot=fullfile('docs','lls','evidence_20260913','received_harq_outcomes_04');
old=readtable(fullfile(inputRoot,'received_harq_outcomes.csv'),'TextType','string');
assert(height(old)==66);
rows=cell(height(old),1);
for index=1:height(old)
    path=fullfile(inputRoot,"pucch_"+lower(old.Case(index))+".mat");
    saved=load(path);
    [threshold,source]=sixgr.phy.pucch.resolveDetectionThreshold(saved.f.Assignment,policy);
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(saved.waveform,saved.f.Carrier, ...
        saved.f.Assignment,saved.f.Context,'NoiseVariance',NaN, ...
        'NoiseVarianceMode','noncoherent_correlation','DetectionThreshold',threshold);
    % Independent call to the underlying detector, using the same FFT grid.
    rxGrid=sixgr.phy.waveform.ofdmDemodulate(saved.f.Carrier,saved.waveform);
    channel=saved.f.Assignment.Resource.toolboxConfig();
    symbols=nrExtractResources(nrPUCCHIndices(saved.f.Carrier,channel),rxGrid);
    [decoded,~,metric]=nrPUCCHDecode(saved.f.Carrier,channel,1,symbols, ...
        'DetectionThreshold',threshold);
    assert(abs(rx.DetectionMetric-metric)<1e-12 && ...
        isequal(int8(decoded{1}(:)),rx.DecodedSequence1));
    assert(rx.DTX==(metric<threshold) && ...
        abs(rx.DetectionMetric-saved.rx.DetectionMetric)<1e-12);
    if old.SignalPresent(index)
        assert(rx.ReceiverUsable && isequal(rx.DecodedSequence1,saved.rx.DecodedSequence1));
    end
    rows{index}=struct('Case',old.Case(index),'SignalPresent',old.SignalPresent(index), ...
        'InputFile',string(path),'InputSHA256',string(sixgr.util.sha256File(path)), ...
        'PreviousThreshold',saved.rx.DetectionThreshold,'ConfiguredThreshold',threshold, ...
        'DetectionThresholdSource',source,'MetricDomain',"normalized_sequence_correlation", ...
        'DetectionMetric',rx.DetectionMetric,'ToolboxDetectionMetric',double(metric), ...
        'PreviousDetected',saved.rx.ReceiverUsable,'ConfiguredDetected',rx.ReceiverUsable, ...
        'PreviousACKBits',sum(saved.rx.DecodedSequence1==1), ...
        'ConfiguredACKBits',sum(rx.DecodedSequence1==1), ...
        'ConfiguredDTX',rx.DTX,'Source',"actual_retained_IQ_component_replay");
end
comparison=struct2table(vertcat(rows{:}));
writetable(comparison,fullfile(outputRoot,'detector_policy_comparison.csv'));
noise=~logical(comparison.SignalPresent);
count=[sum(comparison.PreviousDetected(noise));sum(comparison.ConfiguredDetected(noise))];
falseACK=[sum(comparison.PreviousACKBits(noise));sum(comparison.ConfiguredACKBits(noise))];
assert(count(1)==60 && count(2)<=count(1));
assert(falseACK(1)==34 && all(falseACK<=count));
summary=table(["previous_0.2";"configured_0.42"],repmat(sum(noise),2,1),count,falseACK, ...
    falseACK/sum(noise),repmat("not_qualified_component_sample_only",2,1), ...
    'VariableNames',{'Policy','NoiseOnlyTrials','FalseDetections','FalseACKBits', ...
    'DTXToACKBitProbability','QualificationStatus'});
writetable(summary,fullfile(outputRoot,'noise_only_summary.csv'));
sixgr.report.plotPUCCHDetectorComparison(summary,fullfile(outputRoot,'noise_only_comparison.png'));
save(fullfile(outputRoot,'resolved_receiver_policy.mat'),'policy','comparison','summary');
fprintf('PUCCH_YAML_DETECTOR_PASS old_false_detections=%d new_false_detections=%d / %d\n', ...
    count(1),count(2),sum(noise));
fprintf('DTX_TO_ACK_BITS old=%d new=%d denominator=%d (not conformance qualification)\n', ...
    falseACK(1),falseACK(2),sum(noise));
ok=true;
end

function localReject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:ExpectedError','Expected %s.',id);
end
