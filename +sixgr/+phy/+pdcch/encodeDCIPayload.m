function dci = encodeDCIPayload(fields, dciFormat, pdcchCfg)
%ENCODEDCIPAYLOAD Serialize strict mini-anchor DCI fields to payload bits.

dciFormat = upper(strrep(string(dciFormat), "-", "_"));
K = double(pdcchCfg.DCIPayloadSizeBits);
layout = localLayout(dciFormat);
bits = zeros(K, 1, "int8");
fieldRows = repmat(localFieldRow(), 0, 1);
cursor = 1;
for ii = 1:numel(layout)
    spec = layout(ii);
    value = double(localFieldValue(fields, spec.Name, 0));
    b = localUIntToBits(value, spec.Width);
    stop = min(K, cursor + spec.Width - 1);
    if cursor <= K
        bits(cursor:stop) = b(1:(stop - cursor + 1));
    end
    row = localFieldRow();
    row.FieldName = string(spec.Name);
    row.Value = double(value);
    row.BitOffsetStart = double(cursor - 1);
    row.BitOffsetEnd = double(stop - 1);
    fieldRows(end + 1, 1) = row; %#ok<AGROW>
    cursor = cursor + spec.Width;
end

hex = sixgr.phy.pdcch.payloadBitsToHex(bits);
dci = struct();
dci.Format = dciFormat;
dci.Direction = string(localFieldValue(fields, "direction", ""));
dci.GrantType = string(localFieldValue(fields, "grant_type", ""));
dci.Fields = fields;
dci.Bits = bits;
dci.PayloadHex = hex;
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

function value = localFieldValue(fields, name, defaultValue)
if isfield(fields, name)
    value = fields.(name);
else
    value = defaultValue;
end
end

function bits = localUIntToBits(value, width)
value = uint64(max(0, floor(double(value))));
bits = zeros(width, 1, "int8");
for ii = 1:width
    shift = width - ii;
    bits(ii) = int8(bitand(bitshift(value, -shift), 1));
end
end

function row = localFieldRow()
row = struct("FieldName", "", "Value", NaN, "BitOffsetStart", NaN, "BitOffsetEnd", NaN);
end
