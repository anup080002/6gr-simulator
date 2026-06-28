function dci = decodeDCIPayload(bits, dciFormat, pdcchCfg)
%DECODEDCIPAYLOAD Parse strict mini-anchor DCI payload bits.

bits = int8(bits(:));
dciFormat = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
[K, sizeDetails] = sixgr.phy.pdcch.dciPayloadSizeBits(double(pdcchCfg.NSizeGrid), dciFormat);
if numel(bits) < K
    bits(end+1:K, 1) = 0;
elseif numel(bits) > K
    bits = bits(1:K);
end
layout = sixgr.phy.pdcch.dciPayloadLayout(dciFormat, pdcchCfg);
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
[prbStart, numPRB, rivValid] = sixgr.phy.pdcch.rivDecode(fields.frequency_resource_assignment, pdcchCfg.NSizeGrid);
fields.prb_start = prbStart;
fields.num_prb = numPRB;
fields.frequency_resource_assignment_valid = logical(rivValid);
if dciFormat == "1_0" || dciFormat == "1_1"
    fields.direction = "DL";
    fields.grant_type = "PDSCH";
    [fields.symbol_start, fields.num_symbols] = localResolveTimeDomainAlloc(fields.time_resource_assignment, "DL");
else
    fields.direction = "UL";
    fields.grant_type = "PUSCH";
    [fields.symbol_start, fields.num_symbols] = localResolveTimeDomainAlloc(fields.time_resource_assignment, "UL");
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
dci.BitExactPDCCHPayload = true;
dci.StandardProfile = "ts_38212_supported_dci_payload";
dci.SizeDetails = sizeDetails;
end

function value = localBitsToUInt(bits)
value = uint64(0);
bits = int8(bits(:));
for ii = 1:numel(bits)
    value = bitshift(value, 1) + uint64(bits(ii) ~= 0);
end
value = double(value);
end

function [symStart, numSymbols] = localResolveTimeDomainAlloc(idx, direction)
idx = double(idx);
direction = upper(string(direction));
if direction == "DL"
    % Default type-A PDSCH allocation rows used by this simulator's NR
    % baseline path. Row 0 matches the mobile scenario: S=2, L=12.
    tableRows = [
        0 2 12
        1 2 10
        2 3 11
        3 2 9
        4 2 7
        5 9 4
        6 4 4
        7 5 7
        8 5 2
        9 9 2
        10 12 2
        11 1 13
        12 1 6
        13 2 4
        14 4 7
        15 8 4];
else
    % Baseline non-transform-precoded PUSCH allocation used in the mobile
    % scenario. Row 0 is full-slot PUSCH: S=0, L=14.
    tableRows = [
        0 0 14
        1 0 12
        2 2 10
        3 4 10
        4 0 7
        5 7 7
        6 0 4
        7 4 4
        8 8 4
        9 10 4
        10 0 2
        11 2 2
        12 4 2
        13 6 2
        14 8 2
        15 10 2];
end
row = tableRows(tableRows(:, 1) == idx, :);
if isempty(row)
    row = tableRows(1, :);
end
symStart = double(row(1, 2));
numSymbols = double(row(1, 3));
end

function row = localFieldRow()
row = struct("FieldName", "", "Value", NaN, "BitOffsetStart", NaN, "BitOffsetEnd", NaN);
end
