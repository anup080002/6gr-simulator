function rnti = computeRARNTI(varargin)
%COMPUTERARNTI Compute RA-RNTI for a PRACH occasion anchor.
%
% Anchor follows the TS 38.321/38.213 form:
% 1 + s_id + 14*t_id + 14*80*f_id + 14*80*8*ul_carrier_id.
p = inputParser;
p.addParameter("SymbolIndex", 0, @(x)isnumeric(x) && isscalar(x));
p.addParameter("SlotIndex", 0, @(x)isnumeric(x) && isscalar(x));
p.addParameter("FrequencyIndex", 0, @(x)isnumeric(x) && isscalar(x));
p.addParameter("ULCarrierId", 0, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
sid = max(0, min(13, round(double(p.Results.SymbolIndex))));
tid = max(0, min(79, round(double(p.Results.SlotIndex))));
fid = max(0, min(7, round(double(p.Results.FrequencyIndex))));
ulid = max(0, min(1, round(double(p.Results.ULCarrierId))));
rnti = double(1 + sid + 14 * tid + 14 * 80 * fid + 14 * 80 * 8 * ulid);
end
