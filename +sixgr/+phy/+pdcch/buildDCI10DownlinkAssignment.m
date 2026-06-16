function dci = buildDCI10DownlinkAssignment(pdcchCfg, varargin)
%BUILDDCI10DOWNLINKASSIGNMENT Build a strict mini-anchor DCI 1_0 payload.

p = inputParser;
addRequired(p, "pdcchCfg", @isstruct);
addParameter(p, "PRBStart", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumPRB", min(24, double(pdcchCfg.NSizeGrid)), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "MCS", 10, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "HARQProcess", 0, @(x) isnumeric(x) && isscalar(x));
parse(p, pdcchCfg, varargin{:});
opt = p.Results;

fields = struct();
fields.format_identifier = 1;
fields.frequency_resource_assignment = localPackFreq(opt.PRBStart, opt.NumPRB);
fields.time_resource_assignment = 2;
fields.vrb_to_prb_mapping = 0;
fields.mcs = double(opt.MCS);
fields.ndi = 1;
fields.rv = 0;
fields.harq_process = double(opt.HARQProcess);
fields.dai = 0;
fields.tpc = 1;
fields.pucch_resource_indicator = 0;
fields.pdsch_to_harq_feedback_timing = 4;
fields.prb_start = double(opt.PRBStart);
fields.num_prb = double(opt.NumPRB);
fields.symbol_start = 2;
fields.num_symbols = 10;
fields.direction = "DL";
fields.grant_type = "PDSCH";

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "1_0", pdcchCfg);
end

function v = localPackFreq(startPRB, numPRB)
v = bitshift(uint32(max(0, round(double(startPRB)))), 7) + uint32(max(1, min(127, round(double(numPRB)))));
v = double(v);
end
