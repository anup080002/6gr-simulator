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
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode(opt.PRBStart, opt.NumPRB, pdcchCfg.NSizeGrid);
fields.time_resource_assignment = 0;
fields.vrb_to_prb_mapping = 0;
fields.mcs = double(opt.MCS);
fields.ndi = 1;
fields.rv = 0;
fields.harq_process = double(opt.HARQProcess);
fields.dai = 0;
fields.tpc_command_for_pucch = 1;
fields.pucch_resource_indicator = 0;
fields.pdsch_to_harq_feedback_timing = 4;

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "1_0", pdcchCfg);
end
