function cqi = normalizeReportedCQI(cqiIn)
%NORMALIZEREPORTEDCQI Normalize user-facing NR CQI to 1..15 or NaN.
%
% 3GPP TS 38.214 defines CQI index 0 as out of range. For exported
% measurement-backed tables we keep valid CQI in 1..15 and map non-reportable
% or out-of-range values to NaN so they are not mistaken for a valid quality
% indication.

cqi = NaN(size(cqiIn));
raw = double(cqiIn);
if isempty(raw)
    return;
end
mask = isfinite(raw);
if ~any(mask, "all")
    return;
end
raw(mask) = round(raw(mask));
validMask = mask & raw >= 1 & raw <= 15;
cqi(validMask) = raw(validMask);
end
