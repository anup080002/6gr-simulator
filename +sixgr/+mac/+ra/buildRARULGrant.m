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
prbStart = localClamp(round(double(sched.PRBStart)), 0, 31);
numPRB = localClamp(round(double(sched.NumPRB)), 1, 31);
timeAssignment = 0; % anchor TDRA: SymbolAllocation=[0 14]
mcs = localClamp(round(double(sched.MCS)), 0, 31);
tpc = 1; % 0 dB anchor command
csiRequest = 0;
transformPrecoding = 0;
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
grant.TransformPrecoding = false;
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

function value = localClamp(value, lo, hi)
value = max(lo, min(hi, value));
end
