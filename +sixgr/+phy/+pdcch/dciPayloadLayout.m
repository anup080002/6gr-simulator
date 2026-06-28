function [layout, sizeDetails] = dciPayloadLayout(dciFormat, pdcchCfg)
%DCIPAYLOADLAYOUT Supported TS 38.212 DCI payload field layout.
%
% This is the repository's executable DCI contract for configured PDCCH
% formats 0_0, 0_1, 1_0 and 1_1. Field widths are the supported runtime
% profile used by the scheduler and strict waveform anchors; unsupported
% format-specific optional fields must be configured out or fail before TX.

dciFormat = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
if isstruct(pdcchCfg)
    nSizeGrid = double(sixgr.util.structGet(pdcchCfg, "NSizeGrid", NaN));
else
    nSizeGrid = double(pdcchCfg);
end
[~, sizeDetails] = sixgr.phy.pdcch.dciPayloadSizeBits(nSizeGrid, dciFormat);
nFreqBits = double(sizeDetails.FrequencyResourceAssignmentBits);

switch dciFormat
    case "1_0"
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "vrb_to_prb_mapping","mcs","ndi","rv","harq_process","dai","tpc", ...
            "pucch_resource_indicator","pdsch_to_harq_feedback_timing"];
        widths = [1 nFreqBits 4 1 5 1 2 4 2 2 3 3];
    case "0_0"
        padBits = max(0, double(sizeDetails.DCI00PaddedPayloadBits) - double(sizeDetails.DCI00UnpaddedPayloadBits));
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "frequency_hopping","mcs","ndi","rv","harq_process","tpc","padding"];
        widths = [1 nFreqBits 4 1 5 1 2 4 2 padBits];
    case "1_1"
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "vrb_to_prb_mapping","prb_bundling_size_indicator","rate_matching_indicator", ...
            "zp_csirs_trigger","mcs","ndi","rv","harq_process","dai","tpc", ...
            "pucch_resource_indicator","pdsch_to_harq_feedback_timing","antenna_ports", ...
            "transmission_configuration_indication","srs_request","csi_request", ...
            "cbg_transmission_information","cbg_flushing_information","dmrs_sequence_initialization"];
        widths = [1 nFreqBits 4 1 1 2 2 5 1 2 4 2 2 3 3 5 3 2 2 8 1 1];
    case "0_1"
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "frequency_hopping","mcs","ndi","rv","harq_process","first_dai", ...
            "tpc_command_for_pusch","srs_resource_indicator", ...
            "precoding_information_and_number_of_layers_tpmi", ...
            "precoding_information_and_number_of_layers_rank_minus1", ...
            "antenna_ports","srs_request","csi_request","k2"];
        widths = [1 nFreqBits 4 1 5 1 2 4 2 2 4 6 2 5 2 2 3];
    otherwise
        error("sixgr:phy:pdcch:UnsupportedDCIFormat", ...
            "Supported bit-exact PDCCH DCI formats are 0_0, 0_1, 1_0 and 1_1; got %s.", dciFormat);
end

keep = widths > 0;
names = names(keep);
widths = widths(keep);
layout = repmat(struct("Name", "", "Width", 0), numel(names), 1);
for ii = 1:numel(names)
    layout(ii).Name = char(names(ii));
    layout(ii).Width = double(widths(ii));
end
end

