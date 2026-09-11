function T=bindSharedLargeScaleEvidence(T,planes)
% Post-decode scoring/export only. The measurement covers full processor
% segments intersecting this RX capture, not a guessed cropped-window mean.
assert(istable(T) && height(T)==1,'sixgr:truth:GainEvidenceTrialScope', ...
    'Bind one completed shared PHY attempt at a time.');
ids=string({planes.ReceiverID});
post=find(endsWith(ids,':post_rf')); tx=find(endsWith(ids,':tx'));
assert(isscalar(post) && isscalar(tx),'sixgr:truth:GainEvidencePlaneScope', ...
    'Identify one actual receiver and its desired transmitter.');
rxID=extractBefore(ids(post),':post_rf'); txID=extractBefore(ids(tx),':tx');
segments=planes(post).Segments; observation=planes(post).Observation;
assert(~isempty(segments) && observation.isComplete(), ...
    'sixgr:truth:GainEvidenceIncomplete','Completed execution segments are required.');
input=0; output=0; expected=0; count=0; tolerance=0;
intervals=zeros(numel(segments),2);
for k=1:numel(segments)
    e=segments{k}.Execution;
    links=e.Links(string({e.Links.RX})==rxID & string({e.Links.TX})==txID);
    assert(isscalar(links) && isfield(links.LossReplay,'GainStageMeasurement'), ...
        'sixgr:truth:MissingExecutedGainEnergy', ...
        'Every segment needs actual desired-link gain-stage energy, not an interferer or loss ledger substitute.');
    m=links.LossReplay.GainStageMeasurement;
    assert(string(m.Source)=="actual_samples_before_after_large_scale_gain" && ...
        ~m.ReceiverEstimatorInput && m.SampleCount==e.EndSampleExclusive-e.StartSample, ...
        'sixgr:truth:GainEnergyExecutionScope','Gain energy must bind to the executed processor interval.');
    input=input+double(m.InputEnergy_mWsample);
    output=output+double(m.OutputEnergy_mWsample);
    expected=expected+double(m.InputEnergy_mWsample)* ...
        10.^(double(links.LossReplay.AppliedLargeScaleGain_dB)/10);
    count=count+double(m.SampleElementCount);
    tolerance=max(tolerance,double(m.RelativeTolerance));
    intervals(k,:)=[e.StartSample e.EndSampleExclusive];
end
assert(intervals(1,1)<=observation.StartSample && ...
    intervals(end,2)>=observation.EndSampleExclusive && ...
    all(intervals(2:end,1)==intervals(1:end-1,2)), ...
    'sixgr:truth:GainEnergyExecutionGap','Execution energy must cover the receive capture without overlapping or missing segments.');
T.LargeScaleInputEnergy_mWsample=input;
T.LargeScaleOutputEnergy_mWsample=output;
T.LargeScaleExpectedOutputEnergy_mWsample=expected;
T.LargeScaleSampleElementCount=count;
T.LargeScalePowerClosureRelativeTolerance=tolerance+8*numel(segments)*eps;
T.LargeScaleMeasurementStartSample=intervals(1,1);
T.LargeScaleMeasurementEndSampleExclusive=intervals(end,2);
T.LargeScaleMeasurementSource="actual_desired_link_gain_stage_full_execution_segments_covering_receive_capture";
T.LargeScaleMeasurementStatus="measured";
if input==0 || output==0 || expected==0
    T.LargeScaleMeasurementStatus="zero_energy_no_finite_attenuation_measurement";
end
end
