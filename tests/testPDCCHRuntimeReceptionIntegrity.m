function ok=testPDCCHRuntimeReceptionIntegrity()
% Main-caller structural guards; actual PHY behavior is exercised by the
% separate receive-boundary, noisy-stream and grant-gate waveform tests.
setup6GRSimToolkit('Verbose',false);
assert(nargin('sixgr.truth.runWaveformLinkBundle')==3);
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
complete=localBody(source,'function r = localCompletePDCCHTrial(', ...
    'function tf = localThermalNoiseSINRUnavailable');
for forbidden=["preparePDCCHTransmission(","localApplyPDCCHChannelAndNoise(", ...
        "applyCompositeReceiverFrontEnd(","initWaveformTruthChannelState(","rxNoise"]
    assert(~contains(complete,forbidden),'A received control reducer must not execute %s.',forbidden);
end
assert(contains(complete,'sixgr.link.completePDCCHReception(') && ...
    contains(complete,'r.FalseAlarmFlag = double(r.PDCCHFalseAlarm)') && ...
    contains(complete,'r.NoiseFalseAlarmFlag = NaN') && ...
    contains(complete,'localDecodeObservedPDCCHGrantDCI('));
physical=localBody(source,'function [y,nVar,replay,updatedRuntimeChannelState] =', ...
    'function sampleRateHz = localResolvePDCCHSampleRate');
assert(numel(strfind(physical,'sixgr.link.applyCompositeReceiverFrontEnd('))==1 && ...
    ~contains(physical,'noiseOnly'),'Primary PDCCH must execute one actual receiver front end.');
assert(~contains(source,'localPDCCHPreAttachAssumptionApplies') && ...
    ~contains(source,'pre_attach_assumed_ok_no_trial_in_warmup') && ...
    ~contains(source,'legacy_addAwgnComplex_last_resort'));
for field=["PDCCHObservationStartSample","PDCCHObservationEndSampleExclusive", ...
        "PDCCHObservationCompletionTime_s","PDCCHMinimumReceiveSamples", ...
        "PDCCHDemodulatedSymbols","PDCCHReceivePaddingApplied"]
    assert(contains(complete,"r."+field+" =") && contains(source,"row."+field+" ="));
end
ok=true;
disp('PDCCH_RUNTIME_RECEPTION_INTEGRITY_STRUCTURE_PASS');
end

function body=localBody(source,first,last)
a=strfind(source,first); b=strfind(source,last);
assert(isscalar(a) && isscalar(b) && a<b);
body=source(a:b-1);
end
