function state=bindSharedPUCCHPresence(state,item,rx)
% Audit after the receiver and protocol reducers. No scoring affects them.
if ~isfield(item.Context,'GNBReception'), return; end
score=sixgr.truth.scoreSharedPUCCHPresence(item,rx,state.SharedWaveformStream.Physical.ConfigurationEpoch);
T=state.ControlTrials.PUCCH;
c=item.Context;
cellID=NaN(height(T),1);
if ismember('ServingCell',T.Properties.VariableNames), cellID=double(T.ServingCell); end
if ismember('BaseStationID',T.Properties.VariableNames)
    base=double(T.BaseStationID); missing=~isfinite(cellID); cellID(missing)=base(missing);
    assert(~any(isfinite(base) & isfinite(cellID) & base~=cellID), ...
        'sixgr:truth:AmbiguousPUCCHPresenceTrial','Contradictory receiver cell identity.');
end
hit=find(T.UEIndex==item.UE & T.Slot==c.Slot & ...
    T.RNTI==score.PresenceRNTI & cellID==score.PresenceServingCell & ...
    string(T.PhysicalPUCCHOccasionId)==score.PresencePhysicalOccasionID & ...
    string(T.ReceiverAssignmentDigest)==score.PresenceReceiverAssignmentDigest & ...
    string(T.ReceiverContextDigest)==string(c.GNBReception.Context.Digest) & ...
    T.ObservationStartSample==score.PresenceRXStartSample & ...
    T.ObservationEndSampleExclusive==score.PresenceRXEndSampleExclusive & ...
    T.ObservationSampleRateHz==score.PresenceSampleRateHz);
assert(isscalar(hit),'sixgr:truth:AmbiguousPUCCHPresenceTrial', ...
    'Bind scoring to exactly one completed physical receiver trial.');
for name=string(fieldnames(score)).'
    value=score.(name);
    if ~ismember(name,string(T.Properties.VariableNames))
        if isstring(value), T.(name)=repmat("",height(T),1);
        elseif islogical(value), T.(name)=false(height(T),1);
        else, T.(name)=NaN(height(T),1); end
    end
    T.(name)(hit)=value;
end
state.ControlTrials.PUCCH=T;
% Standalone SR has an explicit emitted-positive/absent procedure. Replace
% legacy preparation-based scoring only; the received SR action is untouched.
if isfield(c.GNBReception,'SRReportCalendar') && isempty(c.GNBReception.CSIReportConfiguration)
    sr=state.SharedGNBSRReceptionTable;
    j=find(string(sr.ObservationID)==string(item.ID) & sr.UEIndex==item.UE & ...
        sr.RNTI==score.PresenceRNTI & sr.ServingCell==score.PresenceServingCell);
    assert(isscalar(j),'sixgr:truth:AmbiguousPUCCHPresenceTrial','One SR receipt must own the observation.');
    falseSR=NaN; missedSR=NaN;
    if score.SignalPresent==0, falseSR=double(sr.PositiveSRDetected(j)); end
    if score.SignalPresent==1, missedSR=double(~sr.PositiveSRDetected(j)); end
    for name=["UETransmissionExecuted","FalseSRDetection","MissedSRDetection"]
        sr.(name)=double(sr.(name));
    end
    sr.UETransmissionExecuted(j)=score.SignalPresent;
    sr.FalseSRDetection(j)=falseSR; sr.MissedSRDetection(j)=missedSR;
    state.SharedGNBSRReceptionTable=sr;
    state.ControlTrials.PUCCH.FalseSRDetection=double(state.ControlTrials.PUCCH.FalseSRDetection);
    state.ControlTrials.PUCCH.MissedSRDetection=double(state.ControlTrials.PUCCH.MissedSRDetection);
    state.ControlTrials.PUCCH.FalseSRDetection(hit)=falseSR;
    state.ControlTrials.PUCCH.MissedSRDetection(hit)=missedSR;
end
end
