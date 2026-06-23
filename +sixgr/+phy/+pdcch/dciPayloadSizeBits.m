function [payloadBits, details] = dciPayloadSizeBits(nSizeGrid, dciFormats)
%DCIPAYLOADSIZEBITS Resolve NR DCI 0_0/1_0 payload size for a carrier BWP.
%
% The common-size rule for DCI format 0_0/1_0 is handled by padding the
% shorter 0_0 payload to the corresponding 1_0 payload size.

if nargin < 2 || isempty(dciFormats)
    dciFormats = ["1_0", "0_0"];
end
nSizeGrid = double(nSizeGrid);
if ~(isscalar(nSizeGrid) && isfinite(nSizeGrid) && nSizeGrid >= 1)
    error("sixgr:phy:pdcch:InvalidNSizeGrid", ...
        "NSizeGrid must be a positive scalar to derive DCI payload size.");
end
dciFormats = unique(upper(strrep(string(dciFormats(:)), "-", "_")), "stable");
nFreqBits = ceil(log2(nSizeGrid * (nSizeGrid + 1) / 2));
size10 = 1 + nFreqBits + 4 + 1 + 5 + 1 + 2 + 4 + 2 + 2 + 3 + 3;
size00Unpadded = 1 + nFreqBits + 4 + 1 + 5 + 1 + 2 + 4 + 2;
commonSize = size10;
sizes = zeros(numel(dciFormats), 1);
for ii = 1:numel(dciFormats)
    switch dciFormats(ii)
        case "1_0"
            sizes(ii) = size10;
        case "0_0"
            sizes(ii) = commonSize;
        otherwise
            error("sixgr:phy:pdcch:UnsupportedDCIFormat", ...
                "Supported strict PDCCH DCI formats are 1_0 and 0_0; got %s.", dciFormats(ii));
    end
end
payloadBits = double(max(sizes));
details = struct();
details.NSizeGrid = double(nSizeGrid);
details.FrequencyResourceAssignmentBits = double(nFreqBits);
details.DCI10PayloadBits = double(size10);
details.DCI00UnpaddedPayloadBits = double(size00Unpadded);
details.DCI00PaddedPayloadBits = double(commonSize);
details.PayloadBits = double(payloadBits);
details.Formats = dciFormats(:).';
details.SizeSource = "ts_38212_dci_0_0_1_0_common_size_with_ts_38214_riv_bits";
end
