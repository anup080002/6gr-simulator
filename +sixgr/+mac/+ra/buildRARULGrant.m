function grant = buildRARULGrant(raCfg, varargin)
%BUILDRARULGRANT Encode the anchor MSG3 PUSCH grant into 27 MAC RAR bits.

p = inputParser;
p.addParameter("MCS", [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

sched = raCfg.Msg3PUSCH;
if ~isempty(opt.MCS)
    sched.MCS = double(opt.MCS);
end
prbStart = localIntegerRange(sched.PRBStart, 0, 31, "PRBStart");
numPRB = localIntegerRange(sched.NumPRB, 1, 31, "NumPRB");
if prbStart + numPRB > double(raCfg.NSizeGrid)
    error("sixgr:mac:ra:InvalidRARULGrant", ...
        "Msg3 PRB allocation exceeds the active UL BWP.");
end
if double(sched.SymbolStart) ~= 0 || double(sched.NumSymbols) ~= 14
    error("sixgr:mac:ra:InvalidRARULGrant", ...
        "The bounded RAR TDRA row requires Msg3 SymbolAllocation=[0 14].");
end
timeAssignment = 0; % anchor TDRA: SymbolAllocation=[0 14]
mcs = localIntegerRange(sched.MCS, 0, 31, "MCS");
tpc = 1; % 0 dB anchor command
csiRequest = 0;
transformPrecoding = double(logical(sched.TransformPrecoding));
freqAssignment = prbStart * 32 + numPRB;

bits = [ ...
    0; ...
    localIntToBits(freqAssignment, 10); ...
    localIntToBits(timeAssignment, 4); ...
    localIntToBits(mcs, 5); ...
    localIntToBits(tpc, 3); ...
    csiRequest; ...
    transformPrecoding; ...
    0; 0];
bits = int8(bits(:));

grant = struct();
grant.FrequencyHoppingFlag = false;
grant.FrequencyAssignment = double(freqAssignment);
grant.PRBStart = double(prbStart);
grant.NumPRB = double(numPRB);
grant.TimeResourceAssignment = double(timeAssignment);
grant.SymbolStart = 0;
grant.NumSymbols = 14;
grant.MCS = double(mcs);
grant.Modulation = string(sched.Modulation);
grant.TargetCodeRate = double(sched.TargetCodeRate);
grant.TPCCommand = double(tpc);
grant.CSIRequest = false;
grant.TransformPrecoding = logical(transformPrecoding);
grant.RV = double(sched.RV);
grant.NLayers = double(sched.NLayers);
grant.BitVector = bits;
grant.ULGrantHex = sixgr.rrc.asn1.bitsToHex(bits);
grant.Valid = true;
grant.ValidationStatus = "OK";
end

function bits = localIntToBits(value, nBits)
value = uint32(value);
bits = zeros(nBits, 1, "int8");
for ii = 1:nBits
    shift = nBits - ii;
    bits(ii) = int8(bitand(bitshift(value, -shift), 1));
end
end

function value = localIntegerRange(raw, lo, hi, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= lo && value <= hi)
    error("sixgr:mac:ra:InvalidRARULGrant", ...
        "%s must be an integer in [%d,%d].", name, lo, hi);
end
end
