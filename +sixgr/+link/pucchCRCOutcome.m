function outcome=pucchCRCOutcome(applicable,receivedCRC)
% Label only the recorded receiver CRC result, never a TX bit comparison,
% overall trial status, HARQ ACK value, or downstream state transition.
id='sixgr:link:InvalidPUCCHCRCObservation';
assert((isnumeric(applicable)||islogical(applicable)) && isreal(applicable) && ...
    isscalar(applicable) && isfinite(applicable) && any(applicable==[0 1]), ...
    id,'CRC applicability must be a recorded scalar boolean.');
if ~applicable
    outcome="not_applicable";
    return;
end
assert((isnumeric(receivedCRC)||islogical(receivedCRC)) && isreal(receivedCRC) && ...
    isscalar(receivedCRC) && (isnan(receivedCRC)||any(receivedCRC==[0 1])), ...
    id,'A received CRC result must be zero, one, or NaN for missing evidence.');
outcome="unavailable";
if receivedCRC==1
    outcome="pass";
elseif receivedCRC==0
    outcome="fail";
end
end
