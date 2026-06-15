function sched = scheduleMsg2RAR(raCfg, varargin)
%SCHEDULEMSG2RAR Build DCI format 1_0 anchor bits and PDSCH allocation.
p = inputParser;
p.addParameter("RNTI", raCfg.RARNTI, @(x)isnumeric(x) && isscalar(x));
p.addParameter("DCIFormat", "1_0", @(x)ischar(x) || isstring(x));
p.parse(varargin{:});

pdsch = localPDSCHConfig(raCfg, raCfg.Msg2PDSCH, double(p.Results.RNTI));
dciBits = localBuildDCI32(raCfg.Msg2PDSCH, double(raCfg.Msg2PDSCH.RV));
sched = struct();
sched.RNTI = double(p.Results.RNTI);
sched.DCIFormat = string(p.Results.DCIFormat);
sched.DCIBits = dciBits;
sched.PDSCH = pdsch;
sched.PRBStart = double(raCfg.Msg2PDSCH.PRBStart);
sched.NumPRB = double(raCfg.Msg2PDSCH.NumPRB);
sched.SymbolStart = double(raCfg.Msg2PDSCH.SymbolStart);
sched.NumSymbols = double(raCfg.Msg2PDSCH.NumSymbols);
sched.MCS = 0;
sched.Modulation = string(raCfg.Msg2PDSCH.Modulation);
sched.TargetCodeRate = double(raCfg.Msg2PDSCH.TargetCodeRate);
sched.RV = double(raCfg.Msg2PDSCH.RV);
end

function pdsch = localPDSCHConfig(raCfg, s, rnti)
pdsch = nrPDSCHConfig;
pdsch.PRBSet = double(s.PRBStart):(double(s.PRBStart) + double(s.NumPRB) - 1);
pdsch.SymbolAllocation = [double(s.SymbolStart) double(s.NumSymbols)];
pdsch.Modulation = char(string(s.Modulation));
pdsch.NumLayers = double(s.NLayers);
pdsch.RNTI = double(rnti);
pdsch.NID = double(raCfg.NCellID);
try
    pdsch.DMRS.DMRSAdditionalPosition = 2;
catch
end
end

function bits = localBuildDCI32(s, rv)
bits = int8([ ...
    localIntToBits(round(double(s.PRBStart)), 8); ...
    localIntToBits(round(double(s.NumPRB)), 8); ...
    localIntToBits(round(double(s.SymbolStart)), 4); ...
    localIntToBits(round(double(s.NumSymbols)), 4); ...
    localIntToBits(round(double(s.MCS)), 5); ...
    localIntToBits(round(double(rv)), 2); ...
    1]);
end

function bits = localIntToBits(value, nBits)
value = uint32(max(0, value));
bits = zeros(nBits, 1, "int8");
for ii = 1:nBits
    bits(ii) = int8(bitand(bitshift(value, -(nBits - ii)), 1));
end
end
