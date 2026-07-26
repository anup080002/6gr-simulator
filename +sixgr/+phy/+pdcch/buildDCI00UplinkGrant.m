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
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode(opt.PRBStart, opt.NumPRB, pdcchCfg.NSizeGrid);
fields.time_resource_assignment = 0;
fields.frequency_hopping = 0;
fields.mcs = double(opt.MCS);
fields.ndi = 1;
fields.rv = 0;
fields.harq_process = double(opt.HARQProcess);
fields.tpc_command_for_pusch = 1;

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "0_0", pdcchCfg);
end
