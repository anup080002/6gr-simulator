function crc=readCRCObservations(T)
% Received CRC: 1=pass, 0=fail, NaN=no valid observation.
% Never rescue the authoritative column from an alias or execution Status.
n=height(T); crc=nan(n,1);
if ismember('CRCPass',T.Properties.VariableNames)
    value=T.CRCPass;
elseif ismember('TBCrcPass',T.Properties.VariableNames)
    value=T.TBCrcPass;
else
    return;
end
if isnumeric(value) || islogical(value)
    if ~isreal(value) || numel(value)~=n, return; end
    value=double(value(:));
    valid=isfinite(value) & (value==0 | value==1);
    crc(valid)=value(valid);
else
    value=lower(strtrim(string(value)));
    if numel(value)~=n, return; end
    value=value(:);
    crc(ismember(value,["true","yes","pass","passed","ok"]))=1;
    crc(ismember(value,["false","no","fail","failed"]))=0;
    number=str2double(value);
    valid=isfinite(number) & (number==0 | number==1);
    crc(valid)=number(valid);
end
end
