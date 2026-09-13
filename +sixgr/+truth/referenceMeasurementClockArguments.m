function args=referenceMeasurementClockArguments(state,T,signalType,targetType,targetId,knowledgeSlot)
% Read the actual physical owner; never infer knowledge from a measurement's
% availability. Planning snapshots freeze the sample as well as the slot.
args={};
if isempty(T), return; end
required={'SignalType','TargetType','TargetId','Valid'};
assert(all(ismember(required,T.Properties.VariableNames)), ...
    'sixgr:truth:MeasurementConsumerSchema','Reference measurements need identity and validity.');
valid=T.Valid;
assert((isnumeric(valid)||islogical(valid)) && isreal(valid) && iscolumn(valid) && ...
    numel(valid)==height(T) && all(isfinite(double(valid))) && all(valid==0 | valid==1), ...
    'sixgr:phy:refsig:InvalidMeasurementValidity','Measurement validity must be explicitly binary.');
mask=upper(string(T.SignalType))==upper(string(signalType)) & ...
    upper(string(T.TargetType))==upper(string(targetType)) & double(T.TargetId)==targetId & valid==1;
if ~any(mask), return; end
clocked=false(height(T),1);
if ismember('MeasurementClockDomain',T.Properties.VariableNames)
    clocked=string(T.MeasurementClockDomain)=="shared_receiver_sample_clock/v1";
end
for name=["ObservationStartSample","ObservationEndSampleExclusive", ...
        "ObservationSampleRateHz","ResultAvailableAtSample","MeasurementClockEpoch"]
    if ismember(name,T.Properties.VariableNames) && isnumeric(T.(name))
        clocked=clocked | ~isnan(T.(name));
    end
end
if ~any(mask & clocked), return; end
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
assert(isa(owner,'sixgr.truth.CoupledWaveformStream') && isscalar(owner), ...
    'sixgr:truth:MeasurementPhysicalClockRequired', ...
    'Clocked runtime measurement consumers require the actual shared physical owner.');
fs=owner.SampleRateHz; now=owner.Events.NextSampleIndex;
epoch=owner.Physical.ConfigurationEpoch;
if string(sixgr.util.structGet(state,'RuntimeViewMode','execution'))=="future_ul_grant_planning"
    names={'PlanningDecisionSample','PlanningDecisionSampleRateHz','PlanningDecisionClockEpoch'};
    assert(all(isfield(state,names)), ...
        'sixgr:truth:MeasurementPlanningClockRequired','A planning view must retain its actual decision sample clock.');
    sample=state.PlanningDecisionSample;
    assert(isnumeric(sample) && isreal(sample) && isscalar(sample) && isfinite(sample) && ...
        sample>=0 && sample==fix(sample) && sample<=now && ...
        isequal(state.PlanningDecisionSampleRateHz,fs) && isequal(state.PlanningDecisionClockEpoch,epoch), ...
        'sixgr:truth:MeasurementPlanningClockMismatch','Planning knowledge cannot advance with a shared mutable handle.');
    now=double(sample);
end
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
validateattributes(knowledgeSlot,{'numeric'},{'real','scalar','finite','integer','positive'});
available=double(T.AvailableSlot(mask));
available=available(isfinite(available));
validateattributes(available,{'numeric'},{'real','integer','positive'});
% Build the exact CP-OFDM calendar, including any explicitly retained future
% result slots. Average slot duration only sizes this array, never sets time.
last=max([knowledgeSlot; available(:); ceil(now/fs*1000*carrier.SubcarrierSpacing/15)+2]);
boundaries=arrayfun(@(slot)sixgr.phy.frame.slotStartSample(carrier,slot,fs),0:last);
% Historical slot requests cannot acquire knowledge from a later physical
% event. Current-slot calls keep the owner's exact intra-slot position.
sample=min(now,boundaries(knowledgeSlot+1)-1);
slot=find(boundaries<=sample,1,'last');
args={'KnownAtSlot',slot,'KnownAtSample',sample,'ClockSampleRateHz',fs, ...
    'ClockEpoch',epoch,'SlotStartSamples',boundaries};
end
