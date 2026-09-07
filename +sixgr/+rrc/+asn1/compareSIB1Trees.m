function [equal, detail] = compareSIB1Trees(txTree, rxTree)
%COMPARESIB1TREES Compare normalized SIB1 IE trees and hashes.

txNorm = localNormalize(txTree);
rxNorm = localNormalize(rxTree);
txJson = jsonencode(txNorm);
rxJson = jsonencode(rxNorm);
equal = isequal(txJson, rxJson);
detail = struct( ...
    "Equal", logical(equal), ...
    "TxTreeHash", sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(txJson, "UTF-8"))), ...
    "RxTreeHash", sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(rxJson, "UTF-8"))));
end

function out = localNormalize(in)
if isstruct(in)
    out = orderfields(in);
    f = fieldnames(out);
    for idx = 1:numel(out)
        for k = 1:numel(f)
            out(idx).(f{k}) = localNormalize(out(idx).(f{k}));
            % ASN.1 SEQUENCE OF remains a list with one item. MATLAB's
            % jsondecode collapses a homogeneous singleton object list to
            % a scalar struct; YAML can instead supply a cell list.
            if strcmp(f{k},'commonSearchSpaceList') && isstruct(out(idx).(f{k}))
                out(idx).(f{k}) = num2cell(out(idx).(f{k}));
            end
        end
    end
elseif iscell(in)
    out = in;
    for k = 1:numel(out)
        out{k} = localNormalize(out{k});
    end
elseif isstring(in)
    if isscalar(in)
        out = char(in);
    else
        out = cellstr(in);
    end
else
    out = in;
end
end
