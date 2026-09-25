function evidence = classifyCompletedAcquisitionOutage(raw, expectedSlots)
%CLASSIFYCOMPLETEDACQUISITIONOUTAGE Explain absent data, never qualify a link.
% Only a completed shared physical execution with failed acquisition and no
% issued/transmitted data can explain empty primary data-trial tables.
evidence=sixgr.link.classifyCompletedNoDataExecution(raw,expectedSlots);
if ~evidence.Recognized, return; end
evidence.Recognized=false;
owner=raw.CoupledRuntime.SharedWaveformStream;
endSample=double(owner.Events.NextSampleIndex);
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
evidence.PBCHAttempts=height(B);
end
