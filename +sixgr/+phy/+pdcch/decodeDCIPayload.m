function dci = decodeDCIPayload(bits, dciFormat, pdcchCfg)
%DECODEDCIPAYLOAD Parse strict mini-anchor DCI payload bits.

bits = int8(bits(:));
dciFormat = upper(strrep(string(dciFormat), "-", "_"));
K = double(pdcchCfg.DCIPayloadSizeBits);
if numel(bits) < K
    bits(end+1:K, 1) = 0;
elseif numel(bits) > K
    bits = bits(1:K);
end
layout = localLayout(dciFormat);
fields = struct();
fieldRows = repmat(localFieldRow(), 0, 1);
cursor = 1;
for ii = 1:numel(layout)
    spec = layout(ii);
    stop = min(K, cursor + spec.Width - 1);
    if cursor <= K
        value = localBitsToUInt(bits(cursor:stop));
    else
        value = 0;
    end
    fields.(spec.Name) = double(value);
    row = localFieldRow();
    row.FieldName = string(spec.Name);
    row.Value = double(value);
    row.BitOffsetStart = double(cursor - 1);
    row.BitOffsetEnd = double(stop - 1);
    fieldRows(end + 1, 1) = row; %#ok<AGROW>
    cursor = cursor + spec.Width;
end
[prbStart, numPRB] = localUnpackFreq(fields.frequency_resource_assignment);
fields.prb_start = prbStart;
fields.num_prb = numPRB;
if dciFormat == "1_0"
    fields.direction = "DL";
    fields.grant_type = "PDSCH";
    fields.symbol_start = 2;
    fields.num_symbols = 10;
else
    fields.direction = "UL";
    fields.grant_type = "PUSCH";
    fields.symbol_start = 0;
    fields.num_symbols = 12;
end

dci = struct();
dci.Format = dciFormat;
dci.Direction = string(fields.direction);
dci.GrantType = string(fields.grant_type);
dci.Fields = fields;
dci.Bits = bits;
dci.PayloadHex = sixgr.phy.pdcch.payloadBitsToHex(bits);
dci.PayloadHash = sixgr.rrc.asn1.sha256Hex(uint8(bits(:)));
dci.FieldTable = struct2table(fieldRows, "AsArray", true);
end

function layout = localLayout(dciFormat)
switch dciFormat
    case "1_0"
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "vrb_to_prb_mapping","mcs","ndi","rv","harq_process","dai","tpc", ...
            "pucch_resource_indicator","pdsch_to_harq_feedback_timing"];
        widths = [1 14 4 1 5 1 2 4 2 2 3 3];
    case "0_0"
        names = ["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
            "frequency_hopping","mcs","ndi","rv","harq_process","tpc","csi_request"];
        widths = [1 14 4 1 5 1 2 4 2 1];
    otherwise
        error("sixgr:phy:pdcch:UnsupportedDCIFormat", ...
            "Strict PDCCH mini-anchor supports DCI formats 1_0 and 0_0; got %s.", dciFormat);
end
layout = repmat(struct("Name", "", "Width", 0), numel(names), 1);
for ii = 1:numel(names)
    layout(ii).Name = char(names(ii));
    layout(ii).Width = widths(ii);
end
end

function value = localBitsToUInt(bits)
value = uint64(0);
bits = int8(bits(:));
for ii = 1:numel(bits)
    value = bitshift(value, 1) + uint64(bits(ii) ~= 0);
end
value = double(value);
end

function [startPRB, numPRB] = localUnpackFreq(value)
u = uint32(max(0, round(double(value))));
startPRB = double(bitshift(u, -7));
numPRB = double(bitand(u, uint32(127)));
end

function row = localFieldRow()
row = struct("FieldName", "", "Value", NaN, "BitOffsetStart", NaN, "BitOffsetEnd", NaN);
end
