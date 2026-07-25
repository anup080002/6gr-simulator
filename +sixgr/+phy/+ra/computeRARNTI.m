function rnti = computeRARNTI(varargin)
%COMPUTERARNTI Compute RA-RNTI for an exact PRACH occasion.
%
% TS 38.321:
% 1 + s_id + 14*t_id + 14*80*f_id + 14*80*8*ul_carrier_id.
p = inputParser;
p.addParameter("SymbolIndex", 0, @localIntegerScalar);
p.addParameter("SlotIndex", 0, @localIntegerScalar);
p.addParameter("FrequencyIndex", 0, @localIntegerScalar);
p.addParameter("ULCarrierId", 0, @localIntegerScalar);
p.parse(varargin{:});
sid = double(p.Results.SymbolIndex);
tid = double(p.Results.SlotIndex);
fid = double(p.Results.FrequencyIndex);
ulid = double(p.Results.ULCarrierId);
if sid < 0 || sid > 13 || tid < 0 || tid > 79 || ...
        fid < 0 || fid > 7 || ulid < 0 || ulid > 1
    error("sixgr:phy:ia:InvalidRARNTICoordinates", ...
        "RA-RNTI coordinates require s_id=[0,13], t_id=[0,79], " + ...
        "f_id=[0,7], and ul_carrier_id=[0,1].");
end
rnti = double(1 + sid + 14 * tid + 14 * 80 * fid + 14 * 80 * 8 * ulid);
end

function tf = localIntegerScalar(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value == fix(value);
end
