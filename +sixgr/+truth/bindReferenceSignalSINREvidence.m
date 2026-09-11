function row=bindReferenceSignalSINREvidence(row,receiver,channel)
% Bind actual SRS/TRS receiver measurements, without inventing detection,
% strict qualification, scheduler SINR or a missing numerical value.
channel=string(channel);
assert(isscalar(channel) && any(channel==["SRS","TRS"]), ...
    'sixgr:truth:InvalidReferenceSignalSINRChannel','Expected SRS or TRS.');
prefix="MeasuredTrialSINR";
if channel=="SRS", prefix="SINR"; end
value=double(sixgr.util.structGet(receiver,prefix+"_dB",NaN));
validateattributes(value,{'double'},{'scalar','real'});
for metric=["ReceiverHestSINR","MeasuredTrialSINR"]
    row.(metric+"_dB")=value;
    for suffix=["Source","ValueStatus","ValueRole","NAReason"]
        row.(metric+suffix)=string(sixgr.util.structGet(receiver,prefix+suffix,""));
    end
end
available=sixgr.util.structGet(receiver,'ChannelEstimateAvailable',false);
assert((islogical(available)||isnumeric(available)) && isscalar(available) && ...
    any(double(available)==[0 1]),'sixgr:truth:InvalidSINREstimateAvailability', ...
    'Receiver channel-estimate availability must be an explicit boolean.');
row.ReceiverHestSINRApplicable=logical(available) && isfinite(value) && ...
    sixgr.util.isAcceptableSINRStatus(row.ReceiverHestSINRValueStatus);
% Preserve contradictory finite-but-unavailable evidence so the auditor can
% report it. A reporting adapter must neither erase it nor mark it valid.
row.SINRMeasurementDomain=string(sixgr.util.structGet(receiver,'SINRMeasurementDomain',""));
row.PowerReferencePlane=string(sixgr.util.structGet(receiver,'PowerReferencePlane',""));
end
