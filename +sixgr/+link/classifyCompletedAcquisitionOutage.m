function evidence = classifyCompletedAcquisitionOutage(raw, expectedSlots)
%CLASSIFYCOMPLETEDACQUISITIONOUTAGE Explain absent data, never qualify a link.
% Only a completed shared physical execution with failed acquisition and no
% issued/transmitted data can explain empty primary data-trial tables.
evidence=struct('Recognized',false,'Reason',"missing_execution_evidence", ...
    'CompletedSlots',0,'PBCHAttempts',0,'DataTrialsAvailable',false, ...
    'ScenarioPass',false,'DataBLERAvailable',false,'DataConstellationAvailable',false);
if ~isstruct(raw) || ~isscalar(raw) || ...
        ~isnumeric(expectedSlots) || ~isscalar(expectedSlots) || ...
        ~isfinite(expectedSlots) || expectedSlots<1 || expectedSlots~=fix(expectedSlots)
    return;
end
for direction=["DL","UL"]
    if ~isfield(raw,direction) || ~istable(raw.(direction)), return; end
    if ~isempty(raw.(direction))
        evidence.Reason="data_trials_present"; return;
    end
end
state=sixgr.util.structGet(raw,'CoupledRuntime',struct());
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
if ~isa(owner,'sixgr.truth.CoupledWaveformStream') || isempty(owner.Events)
    return;
end
if ~isempty(owner.DataTransmissions)
    evidence.Reason="data_transmitted_but_trials_missing"; return;
end
slots=sixgr.util.structGet(state,'SlotTraceTable',table());
fields=["CanonicalSlot","DLGrantCount","ULGrantCount", ...
    "DLExecutedGrantCount","ULExecutedGrantCount"];
if ~istable(slots) || ~all(ismember(fields,string(slots.Properties.VariableNames))) || ...
        height(slots)~=expectedSlots || ...
        ~isequal(double(slots.CanonicalSlot(:)),(1:expectedSlots).')
    evidence.Reason="incomplete_slot_execution"; return;
end
counts=slots{:,cellstr(fields(2:end))};
if ~isnumeric(counts) || ~all(counts(:)==0)
    evidence.Reason="issued_data_grants_without_trials"; return;
end
duration=sixgr.util.structGet(state,'SlotDuration_s',NaN);
endSample=expectedSlots*double(duration)*double(owner.SampleRateHz);
if ~isscalar(endSample) || ~isfinite(endSample) || endSample<=0 || ...
        abs(double(owner.Events.NextSampleIndex)-endSample)>1e-6
    evidence.Reason="incomplete_physical_clock"; return;
end
B=sixgr.util.structGet(raw,'PBCH',table());
required=["CRCPass","Crash","SSBIdentityVerified","SelectedBeamFlag", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"];
if ~istable(B) || isempty(B) || ~all(ismember(required,string(B.Properties.VariableNames)))
    evidence.Reason="missing_acquisition_trials"; return;
end
crc=sixgr.kpi.readCRCObservations(B);
if ~all(crc==0) || ~all(B.Crash==0) || ...
        ~all(B.SSBIdentityVerified==0) || ~all(B.SelectedBeamFlag==0)
    evidence.Reason="acquisition_not_proven_failed"; return;
end
first=double(B.ObservationStartSample); last=double(B.ObservationEndSampleExclusive);
if ~all(isfinite(first) & isfinite(last) & first>=0 & last>first & last<=endSample) || ...
        ~all(B.ObservationSampleRateHz==owner.SampleRateHz)
    evidence.Reason="invalid_acquisition_observation_clock"; return;
end
evidence.Recognized=true;
evidence.Reason="completed_physical_acquisition_outage_no_data_transmitted";
evidence.CompletedSlots=height(slots);
evidence.PBCHAttempts=height(B);
end
