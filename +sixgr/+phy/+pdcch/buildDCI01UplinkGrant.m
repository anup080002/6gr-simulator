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
fields.srs_resource_indicator = double(opt.SRSResourceIndicator);
fields.precoding_information_and_number_of_layers = ...
    double(opt.TPMI) + 16 * (double(opt.NumLayers) - 1);
fields.antenna_ports = double(opt.NumLayers) - 1;
fields.srs_request = 0;
fields.csi_request = 0;

dci = sixgr.phy.pdcch.encodeDCIPayload(fields, "0_1", pdcchCfg);
end
