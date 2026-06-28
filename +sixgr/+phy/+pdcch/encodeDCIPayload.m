function dci = encodeDCIPayload(fields, dciFormat, pdcchCfg)
%ENCODEDCIPAYLOAD Serialize strict mini-anchor DCI fields to payload bits.

dciFormat = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
[K, sizeDetails] = sixgr.phy.pdcch.dciPayloadSizeBits(double(pdcchCfg.NSizeGrid), dciFormat);
layout = sixgr.phy.pdcch.dciPayloadLayout(dciFormat, pdcchCfg);
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
dci.BitExactPDCCHPayload = true;
dci.StandardProfile = "ts_38212_supported_dci_payload";
dci.SizeDetails = sizeDetails;
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
