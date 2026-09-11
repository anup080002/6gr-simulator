function [usable,crcPass]=puschCSIReceiverUsable(harqOut,part1,part2,expectedCounts)
% Validate actual decoder evidence, never transmitted-bit agreement.
e=sixgr.util.structGet(harqOut,'UCIReceiverEvidence',struct());
assert(isstruct(e) && isscalar(e) && all(isfield(e,{'CSI1','CSI2AndConfiguredGrantUCI'})), ...
    'sixgr:truth:MissingPUSCHCSIReceiverEvidence','PUSCH CSI delivery requires retained per-part decoder evidence.');
parts={part1,part2}; names={'CSI1','CSI2AndConfiguredGrantUCI'};
usable=true; applicable=false; crcOK=true;
for k=1:2
    count=expectedCounts(k); v=e.(names{k});
    % Configured-grant UCI is not part of this runtime CSI report contract.
    [partUsable,partCRC]=sixgr.truth.puschUCIFieldUsable(v,parts{k},count);
    if v.CRCApplicable
        applicable=true; crcOK=crcOK && partCRC==1;
    end
    usable=usable && partUsable;
end
usable=usable && crcOK;
crcPass=NaN;
if applicable, crcPass=double(crcOK); end
end
