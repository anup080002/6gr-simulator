function dci = buildDCI11DownlinkAssignment(pdcchCfg, varargin)
%BUILDDCI11DOWNLINKASSIGNMENT Build a supported bit-exact DCI 1_1 payload.

p = inputParser;
addRequired(p, "pdcchCfg", @isstruct);
addParameter(p, "PRBStart", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumPRB", min(24, double(pdcchCfg.NSizeGrid)), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "MCS", 10, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "HARQProcess", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumLayers", 2, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "PMI", 0, @(x) isnumeric(x) && isscalar(x));
parse(p, pdcchCfg, varargin{:});
opt = p.Results;

fields = struct();
fields.format_identifier = 1;
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode(opt.PRBStart, opt.NumPRB, pdcchCfg.NSizeGrid);
fields.time_resource_assignment = 0;
fields.vrb_to_prb_mapping = 0;
fields.prb_bundling_size_indicator = 0;
fields.rate_matching_indicator = 0;
fields.zp_csirs_trigger = 0;
fields.mcs = double(opt.MCS);
fields.ndi = 1;
fields.rv = 0;
fields.harq_process = double(opt.HARQProcess);
fields.dai = 0;
fields.tpc_command_for_pucch = 1;
fields.pucch_resource_indicator = 0;
fields.pdsch_to_harq_feedback_timing = 4;
fields.antenna_ports = double(opt.NumLayers) - 1;
fields.transmission_configuration_indication = double(opt.PMI);
fields.srs_request = 0;
fields.csi_request = 0;
fields.cbg_transmission_information = 0;
fields.cbg_flushing_information = 0;
fields.dmrs_sequence_initialization = 0;
dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "1_1", pdcchCfg);
end
