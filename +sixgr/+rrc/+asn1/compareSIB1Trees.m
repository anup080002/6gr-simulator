function [equal, detail] = compareSIB1Trees(txTree, rxTree)
%COMPARESIB1TREES Compare normalized SIB1 IE trees and hashes.

txNorm = localNormalize(txTree);
rxNorm = localNormalize(rxTree);
txJson = jsonencode(txNorm);
rxJson = jsonencode(rxNorm);
equal = isequal(txJson, rxJson);
detail = struct( ...
    "Equal", logical(equal), ...
    "TxTreeHash", sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(txJson, "UTF-8"))), ...
    "RxTreeHash", sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(rxJson, "UTF-8"))));
end

function out = localNormalize(in)
if isstruct(in)
    out = orderfields(in);
    f = fieldnames(out);
    for idx = 1:numel(out)
        for k = 1:numel(f)
            out(idx).(f{k}) = localNormalize(out(idx).(f{k}));
        end
    end
elseif iscell(in)
    out = in;
    for k = 1:numel(out)
        out{k} = localNormalize(out{k});
    end
elseif isstring(in)
    out = cellstr(in);
else
    out = in;
end
end
