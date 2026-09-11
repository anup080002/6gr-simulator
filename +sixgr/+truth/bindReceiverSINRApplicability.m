function row=bindReceiverSINRApplicability(row)
% Complete the producer's receiver-evidence flag without changing a value,
% CRC decision, source, or unavailable reason. This is not a SINR estimator.
available=sixgr.util.structGet(row,'ChannelEstimateAvailable',false);
assert((islogical(available)||isnumeric(available)) && isscalar(available) && ...
    any(double(available)==[0 1]),'sixgr:truth:InvalidSINREstimateAvailability', ...
    'Receiver channel-estimate availability must be an explicit boolean.');
value=double(sixgr.util.structGet(row,'ReceiverHestSINR_dB',NaN));
validateattributes(value,{'double'},{'scalar','real'});
status=string(sixgr.util.structGet(row,'ReceiverHestSINRValueStatus',""));
assert(isscalar(status),'sixgr:truth:InvalidReceiverSINRStatus', ...
    'One receiver observation must have one SINR evidence status.');
row.ReceiverHestSINRApplicable=logical(available) && isfinite(value) && ...
    sixgr.util.isAcceptableSINRStatus(status);
end
