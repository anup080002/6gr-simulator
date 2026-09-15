function T=bindSharedLargeScaleEvidence(T,planes)
% Post-decode scoring/export only. The measurement covers full processor
% direction-active segments intersecting this RX capture, not a guessed
% cropped-window mean. A drained, reversed TDD link has no gain execution
% toward the old RX: retain that exclusion instead of inventing a record.
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
active=false(numel(segments),1);
desiredIDs=strings(0,1);
for k=1:numel(segments)
    e=segments{k}.Execution;
    links=e.Links(string({e.Links.RX})==rxID & string({e.Links.TX})==txID);
    desiredIDs=[desiredIDs;string({links.ID}).']; %#ok<AGROW>
end
desiredIDs=unique(desiredIDs);
assert(isscalar(desiredIDs),'sixgr:truth:MissingExecutedGainEnergy', ...
    'One actually executed desired link must own the receive capture.');
for k=1:numel(segments)
    e=segments{k}.Execution;
    intervals(k,:)=[e.StartSample e.EndSampleExclusive];
    links=e.Links(string({e.Links.RX})==rxID & string({e.Links.TX})==txID);
    if isempty(links)
        localAssertInactiveDirection(e,planes,observation,desiredIDs,rxID,txID);
        continue;
    end
    assert(isscalar(links) && isfield(links.LossReplay,'GainStageMeasurement'), ...
        'sixgr:truth:MissingExecutedGainEnergy', ...
        'Every segment needs actual desired-link gain-stage energy, not an interferer or loss ledger substitute.');
    m=links.LossReplay.GainStageMeasurement;
    active(k)=true;
    assert(string(m.Source)=="actual_samples_before_after_large_scale_gain" && ...
        ~m.ReceiverEstimatorInput && m.SampleCount==e.EndSampleExclusive-e.StartSample, ...
        'sixgr:truth:GainEnergyExecutionScope','Gain energy must bind to the executed processor interval.');
    input=input+double(m.InputEnergy_mWsample);
    output=output+double(m.OutputEnergy_mWsample);
    expected=expected+double(m.InputEnergy_mWsample)* ...
        10.^(double(links.LossReplay.AppliedLargeScaleGain_dB)/10);
    count=count+double(m.SampleElementCount);
    tolerance=max(tolerance,double(m.RelativeTolerance));
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
T.LargeScaleMeasurementActiveIntervalsJSON=string(jsonencode(intervals(active,:)));
T.LargeScaleMeasurementInactiveIntervalsJSON=string(jsonencode(intervals(~active,:)));
T.LargeScaleMeasurementSource="actual_desired_link_gain_stage_full_execution_segments_covering_receive_capture";
T.LargeScaleMeasurementStatus="measured";
if any(~active)
    T.LargeScaleMeasurementSource="actual_desired_link_gain_stage_direction_active_execution_segments_with_explicit_inactive_intervals";
end
if input==0 || output==0 || expected==0
    T.LargeScaleMeasurementStatus="zero_energy_no_finite_attenuation_measurement";
end
end

function localAssertInactiveDirection(e,planes,observation,linkID,rxID,txID)
assert(isfield(e,'ScoringPlanes'),'sixgr:truth:MissingExecutedGainEnergy', ...
    'Missing gain evidence requires an actual direction-inactive scoring record.');
entries=e.ScoringPlanes;
entry=entries(string({entries.LinkID})==linkID & string({entries.RX})==rxID);
reverse=e.Links(string({e.Links.ID})==linkID);
assert(isscalar(entry) && ~entry.Active && isscalar(reverse) && ...
    string(reverse.RX)~=rxID && string(reverse.TX)~=txID && ...
    string(entry.TX)==string(reverse.TX) && ...
    string(entry.Source)=="actual_link_contribution_after_tx_rf_channel_loss_before_sum_noise_rx_rf", ...
    'sixgr:truth:MissingExecutedGainEnergy', ...
    'Only the same physically reversed link with explicit inactive scoring can lack desired gain energy.');
plane=planes(string({planes.ReceiverID})==string(entry.ID));
assert(isscalar(plane) && plane.Observation.isComplete() && ...
    plane.Observation.StartSample==observation.StartSample && ...
    plane.Observation.EndSampleExclusive==observation.EndSampleExclusive && ...
    plane.Observation.SampleRateHz==observation.SampleRateHz && ...
    plane.Observation.NumReceiveAntennas==observation.NumReceiveAntennas, ...
    'sixgr:truth:MissingExecutedGainEnergy', ...
    'Exclusion requires the actual complete same-window desired-link scoring capture.');
samples=plane.Observation.readComplete();
first=max(e.StartSample,observation.StartSample)-observation.StartSample+1;
last=min(e.EndSampleExclusive,observation.EndSampleExclusive)-observation.StartSample;
assert(first<=last && all(samples(first:last,:)==0,'all'), ...
    'sixgr:truth:InactiveGainEvidenceNonzeroContribution', ...
    'An excluded direction-inactive interval must have an actually captured zero desired-link contribution.');
end
