function dci = buildDCI01UplinkGrant(pdcchCfg, varargin)
%BUILDDCI01UPLINKGRANT Build a supported bit-exact DCI 0_1 payload.

p = inputParser;
addRequired(p, "pdcchCfg", @isstruct);
addParameter(p, "PRBStart", 4, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumPRB", min(12, double(pdcchCfg.NSizeGrid)), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "MCS", 8, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "HARQProcess", 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "NumLayers", 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "TPMI", 0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "SRSResourceIndicator", 0, @(x) isnumeric(x) && isscalar(x));
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
fields.first_dai = 0;
fields.tpc_command_for_pusch = 1;
fields.srs_resource_indicator = max(0, min(15, round(double(opt.SRSResourceIndicator))));
fields.precoding_information_and_number_of_layers_tpmi = max(0, min(63, round(double(opt.TPMI))));
fields.precoding_information_and_number_of_layers_rank_minus1 = max(0, min(3, round(double(opt.NumLayers) - 1)));
fields.antenna_ports = max(0, min(31, round(double(opt.NumLayers) - 1)));
fields.srs_request = 0;
fields.csi_request = 0;
fields.k2 = 1;
fields.prb_start = double(opt.PRBStart);
fields.num_prb = double(opt.NumPRB);
fields.symbol_start = 0;
fields.num_symbols = 14;
fields.direction = "UL";
fields.grant_type = "PUSCH";

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "0_1", pdcchCfg);
end

