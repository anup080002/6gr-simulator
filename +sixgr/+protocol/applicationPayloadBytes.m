function bytes=applicationPayloadBytes(seed,packetId,direction,ueIdx,offsetBytes,count)
% Original deterministic traffic bytes; this is a TX source, not RX evidence.
assert(isscalar(seed) && isfinite(seed) && seed>=0 && seed==fix(seed), ...
    'sixgr:protocol:MissingPayloadSeed','Application byte source requires an integer seed.');
assert(all(isfinite([ueIdx offsetBytes count])) && ueIdx>=1 && offsetBytes>=0 && count>=0 && ...
    all([ueIdx offsetBytes count]==fix([ueIdx offsetBytes count])), ...
    'sixgr:protocol:InvalidApplicationByteRange','Application byte range must be integral.');
identityOffset=sum(double(char(string(packetId)+"|"+upper(string(direction)))))+257*double(ueIdx);
bytes=uint8(mod(double(offsetBytes)+seed+identityOffset+(0:double(count)-1),256));
end
