function [payloadBits, details] = dciPayloadSizeBits(nSizeGrid, dciFormats)
%DCIPAYLOADSIZEBITS Resolve supported NR DCI payload sizes for a carrier BWP.
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
rawFormats = string(dciFormats(:));
dciFormats = strings(numel(rawFormats), 1);
for ii = 1:numel(rawFormats)
    dciFormats(ii) = sixgr.phy.pdcch.normalizeDCIFormat(rawFormats(ii));
end
dciFormats = unique(dciFormats, "stable");
nFreqBits = ceil(log2(nSizeGrid * (nSizeGrid + 1) / 2));
size10 = 1 + nFreqBits + 4 + 1 + 5 + 1 + 2 + 4 + 2 + 2 + 3 + 3;
size00Unpadded = 1 + nFreqBits + 4 + 1 + 5 + 1 + 2 + 4 + 2;
commonSize = size10;
size11 = 1 + nFreqBits + 4 + 1 + 1 + 2 + 2 + 5 + 1 + 2 + 4 + 2 + 2 + 3 + 3 + 5 + 3 + 2 + 2 + 8 + 1 + 1;
size01 = 1 + nFreqBits + 4 + 1 + 5 + 1 + 2 + 4 + 2 + 2 + 4 + 6 + 2 + 5 + 2 + 2 + 3;
sizes = zeros(numel(dciFormats), 1);
for ii = 1:numel(dciFormats)
    switch dciFormats(ii)
        case "1_0"
            sizes(ii) = size10;
        case "0_0"
            sizes(ii) = commonSize;
        case "1_1"
            sizes(ii) = size11;
        case "0_1"
            sizes(ii) = size01;
        otherwise
            error("sixgr:phy:pdcch:UnsupportedDCIFormat", ...
                "Supported bit-exact PDCCH DCI formats are 0_0, 0_1, 1_0 and 1_1; got %s.", dciFormats(ii));
    end
end
payloadBits = double(max(sizes));
details = struct();
details.NSizeGrid = double(nSizeGrid);
details.FrequencyResourceAssignmentBits = double(nFreqBits);
details.DCI10PayloadBits = double(size10);
details.DCI00UnpaddedPayloadBits = double(size00Unpadded);
details.DCI00PaddedPayloadBits = double(commonSize);
details.DCI11PayloadBits = double(size11);
details.DCI01PayloadBits = double(size01);
details.PayloadBits = double(payloadBits);
details.Formats = dciFormats(:).';
details.SizeSource = "ts_38212_supported_dci_0_0_0_1_1_0_1_1_with_ts_38214_riv_bits";
end
