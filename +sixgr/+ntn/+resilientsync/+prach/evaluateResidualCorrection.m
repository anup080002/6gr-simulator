function result = evaluateResidualCorrection(request, state)
%EVALUATERESIDUALCORRECTION Quantize, saturate and activate one correction.

required=["TimingError_s","FrequencyError_Hz","TimingRange_s", ...
    "FrequencyRange_Hz","TimingStep_s","FrequencyStep_Hz", ...
    "ActivationTime_s","StateVersion"];
for name=required,if ~isfield(request,name),error('sixgr:ntn:resilientsync:MissingCorrectionField', ...
        'Correction request is missing %s.',char(name));end,end
if double(request.StateVersion)<double(sixgr.util.structGet(state,'StateVersion',0))
    error('sixgr:ntn:resilientsync:StaleCorrectionState', ...
        'Correction stateVersion %d is older than active version %d.', ...
        request.StateVersion,sixgr.util.structGet(state,'StateVersion',0));
end
timingCommand=round(-double(request.TimingError_s)/double(request.TimingStep_s))*double(request.TimingStep_s);
frequencyCommand=round(-double(request.FrequencyError_Hz)/double(request.FrequencyStep_Hz))*double(request.FrequencyStep_Hz);
timingSaturated=abs(timingCommand)>double(request.TimingRange_s);
frequencySaturated=abs(frequencyCommand)>double(request.FrequencyRange_Hz);
timingCommand=max(-double(request.TimingRange_s),min(double(request.TimingRange_s),timingCommand));
frequencyCommand=max(-double(request.FrequencyRange_Hz),min(double(request.FrequencyRange_Hz),frequencyCommand));
now=double(sixgr.util.structGet(state,'Time_s',0));active=now>=double(request.ActivationTime_s);
alreadyApplied=double(sixgr.util.structGet(state,'AppliedStateVersion',-1))==double(request.StateVersion);
if alreadyApplied
    timingApplied=0;frequencyApplied=0;
elseif active
    timingApplied=timingCommand;frequencyApplied=frequencyCommand;
else
    timingApplied=0;frequencyApplied=0;
end
result=struct('TimingCommand_s',timingCommand,'FrequencyCommand_Hz',frequencyCommand, ...
    'TimingApplied_s',timingApplied,'FrequencyApplied_Hz',frequencyApplied, ...
    'TimingSaturated',timingSaturated,'FrequencySaturated',frequencySaturated, ...
    'Active',active,'AlreadyApplied',alreadyApplied,'StateVersion',double(request.StateVersion), ...
    'ActivationTime_s',double(request.ActivationTime_s));
end
