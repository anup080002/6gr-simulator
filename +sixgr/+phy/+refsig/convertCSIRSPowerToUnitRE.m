function [shifted,offset]=convertCSIRSPowerToUnitRE(value,nfft,scale)
% Undo the exact CSI producer grid/(Nfft*sqrt(1000)) power reference.
% Applies to RX RSRP/RSSI and TX connector EPRE, not to waveform samples.
scaleValid=isscalar(nfft) && isfinite(nfft) && nfft>=1 && nfft==fix(nfft) && ...
    isscalar(scale) && isfinite(scale) && ...
    abs(scale-nfft*sqrt(1000))<=16*eps(nfft*sqrt(1000));
offset=NaN;
if scaleValid, offset=20*log10(nfft); end
if isnumeric(value)
    shifted=localShift(double(value),offset);
    return;
end
value=string(value);
assert(isscalar(value) && ~ismissing(value), ...
    'sixgr:phy:InvalidCSIRSPowerToken','CSI power vectors require one explicit numeric token.');
value=strtrim(value);
if value=="", shifted=value; return; end
assert(startsWith(value,"[") && endsWith(value,"]"), ...
    'sixgr:phy:InvalidCSIRSPowerToken','CSI power vectors must retain the producer bracketed numeric format.');
if strlength(value)==2, shifted="[]"; return; end
body=strtrim(extractBetween(value,2,strlength(value)-1));
if body=="", shifted="[]"; return; end
parts=regexp(char(body),'[\s,;]+','split');
values=str2double(parts);
assert(all(~isnan(values) | strcmpi(parts,'NaN')), ...
    'sixgr:phy:InvalidCSIRSPowerToken','Do not replace malformed CSI power evidence with NaN.');
shifted="["+strjoin(compose('%.15g',localShift(values,offset)),' ')+"]";
end
function shifted=localShift(values,offset)
assert(isreal(values) && (all(isnan(values),'all') || isfinite(offset)), ...
    'sixgr:phy:MissingCSIRSPowerScale', ...
    'Do not convert a retained CSI power without its actual producer FFT size and matching grid-to-watt scale.');
shifted=values+offset;
end
