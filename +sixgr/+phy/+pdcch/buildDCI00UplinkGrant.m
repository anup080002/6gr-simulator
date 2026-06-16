function dci = buildDCI00UplinkGrant(pdcchCfg, varargin)
%BUILDDCI00UPLINKGRANT Build a strict mini-anchor DCI 0_0 payload.

p = inputParser;
addRequired(p, "pdcchCfg", @isstruct);
addParameter(p, "PRBStart", 4, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumPRB", min(12, double(pdcchCfg.NSizeGrid)), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "MCS", 8, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "HARQProcess", 1, @(x) isnumeric(x) && isscalar(x));
parse(p, pdcchCfg, varargin{:});
opt = p.Results;

fields = struct();
fields.format_identifier = 0;
fields.frequency_resource_assignment = localPackFreq(opt.PRBStart, opt.NumPRB);
fields.time_resource_assignment = 1;
fields.frequency_hopping = 0;
fields.mcs = double(opt.MCS);
fields.ndi = 1;
fields.rv = 0;
fields.harq_process = double(opt.HARQProcess);
fields.tpc = 1;
fields.csi_request = 0;
fields.prb_start = double(opt.PRBStart);
fields.num_prb = double(opt.NumPRB);
fields.symbol_start = 0;
fields.num_symbols = 12;
fields.direction = "UL";
fields.grant_type = "PUSCH";

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "0_0", pdcchCfg);
end

function v = localPackFreq(startPRB, numPRB)
v = bitshift(uint32(max(0, round(double(startPRB)))), 7) + uint32(max(1, min(127, round(double(numPRB)))));
v = double(v);
end
