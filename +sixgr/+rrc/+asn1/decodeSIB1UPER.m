function [msg, meta] = decodeSIB1UPER(bitsOrBytes)
%DECODESIB1UPER Decode the supported SIB1 anchor profile.

bits = localNormalizeBits(bitsOrBytes);
if numel(bits) < 20
    error("sixgr:rrc:asn1:DecodeFailed", "SIB1 payload is shorter than the anchor header.");
end
[version, pos] = localReadUInt(bits, 1, 4);
if version ~= 1
    error("sixgr:rrc:asn1:DecodeFailed", "Unsupported SIB1 anchor profile version %d.", version);
end
[bodyLen, pos] = localReadUInt(bits, pos, 16);
if numel(bits) < pos + bodyLen - 1
    error("sixgr:rrc:asn1:DecodeFailed", "SIB1 payload ended before declared body length.");
end
bodyEnd = pos + bodyLen - 1;
body = bits(pos:bodyEnd);
payloadEnd = bodyEnd + mod(8 - mod(bodyEnd, 8), 8);
if numel(bits) < payloadEnd
    error("sixgr:rrc:asn1:DecodeFailed", "SIB1 payload ended before byte alignment padding.");
end
payloadBits = bits(1:payloadEnd);
trailingBits = bits(payloadEnd+1:end);
if any(trailingBits ~= 0)
    error("sixgr:rrc:asn1:DecodeFailed", "SIB1 transport block has non-zero trailing padding after the ASN.1 payload.");
end
p = 1;
[~, p] = localExpectUInt(body, p, 1, 0, "bcchExtension");
[~, p] = localExpectUInt(body, p, 1, 0, "messageChoice");
[~, p] = localExpectUInt(body, p, 3, 0, "c1Choice");
[~, p] = localExpectUInt(body, p, 1, 0, "sib1Extension");
[mcc, p] = localReadDigits(body, p, 3);
[mncIs3, p] = localReadUInt(body, p, 1);
mncLen = 2 + double(mncIs3);
[mnc, p] = localReadDigits(body, p, mncLen);
[tac, p] = localReadUInt(body, p, 24);
[cellIdentity, p] = localReadUInt(body, p, 36);
[reserved, p] = localReadUInt(body, p, 1);
[qRxLevMin, p] = localReadSigned(body, p, -140, 8);
[qQualMin, p] = localReadSigned(body, p, -43, 7);
[scsIdx, p] = localReadUInt(body, p, 2);
[carrierBandwidth, p] = localReadUInt(body, p, 10);
remainingLegacyTailBits = 44;
if bodyLen - p + 1 >= remainingLegacyTailBits + 66
    [absoluteFrequencySSB, p] = localReadUInt(body, p, 22);
    [dlAbsoluteFrequencyPointA, p] = localReadUInt(body, p, 22);
    [ulAbsoluteFrequencyPointA, p] = localReadUInt(body, p, 22);
else
    absoluteFrequencySSB = NaN;
    dlAbsoluteFrequencyPointA = NaN;
    ulAbsoluteFrequencyPointA = NaN;
end
[coreset0, p] = localReadUInt(body, p, 4);
[search0, p] = localReadUInt(body, p, 4);
[dmrsOffset, p] = localReadUInt(body, p, 1);
[periodIdx, p] = localReadUInt(body, p, 3);
[prachIndex, p] = localReadUInt(body, p, 8);
[rootSeq, p] = localReadUInt(body, p, 10);
[zcz, p] = localReadUInt(body, p, 4);
[nPreambles, p] = localReadUInt(body, p, 7);
[formatIdx, ~] = localReadUInt(body, p, 3);

cfg = struct();
cfg.phy.carrier.NCellID = double(cellIdentity);
cfg.phy.carrier.SubcarrierSpacing = localSCSFromIndex(scsIdx, "numeric");
cfg.phy.carrier.NSizeGrid = double(carrierBandwidth);
cfg.rrc.sib1.plmn = char(mcc + mnc);
cfg.rrc.sib1.tac = double(tac);
cfg.rrc.sib1.cellIdentity = double(cellIdentity);
cfg.phy.sib1.coreset0Index = double(coreset0);
cfg.phy.sib1.searchSpaceZero = double(search0);
cfg.phy.mib.dmrsTypeAPosition = double(dmrsOffset) + 2;
cfg.phy.prach.configurationIndex = double(prachIndex);
cfg.phy.prach.rootSeqIndex = double(rootSeq);
cfg.phy.prach.zeroCorrelationZone = double(zcz);
cfg.phy.prach.nPreambles = double(nPreambles);
cfg.phy.prach.preambleFormat = char(localPreambleFormatFromIndex(formatIdx));
msg = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg, "CellID", double(cellIdentity));
msg.message.c1.systemInformationBlockType1.cellSelectionInfo.q_RxLevMin = double(qRxLevMin);
msg.message.c1.systemInformationBlockType1.cellSelectionInfo.q_QualMin = double(qQualMin);
msg.message.c1.systemInformationBlockType1.cellAccessRelatedInfo.cellReservedForOperatorUse = ...
    string(ternary(reserved == 1, "reserved", "notReserved"));
msg.message.c1.systemInformationBlockType1.servingCellConfigCommon.ssb_periodicityServingCell = ...
    localPeriodicityFromIndex(periodIdx);
if isfinite(absoluteFrequencySSB)
    msg.message.c1.systemInformationBlockType1.servingCellConfigCommon.downlinkConfigCommon.frequencyInfoDL.absoluteFrequencySSB = ...
        double(absoluteFrequencySSB);
end
if isfinite(dlAbsoluteFrequencyPointA)
    msg.message.c1.systemInformationBlockType1.servingCellConfigCommon.downlinkConfigCommon.frequencyInfoDL.dl_AbsoluteFrequencyPointA = ...
        double(dlAbsoluteFrequencyPointA);
end
if isfinite(ulAbsoluteFrequencyPointA)
    msg.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.frequencyInfoUL.absoluteFrequencyPointA = ...
        double(ulAbsoluteFrequencyPointA);
end
sixgr.rrc.asn1.validateSIB1ForScenario(msg, cfg);

meta = struct( ...
    "Profile", "sixgr_sib1_anchor_profile_v1", ...
    "PayloadBits", double(numel(payloadBits)), ...
    "BodyBits", double(bodyLen), ...
    "TrailingTransportBlockPaddingBits", double(numel(trailingBits)), ...
    "PayloadHash", sixgr.rrc.asn1.sha256Hex(payloadBits(:)), ...
    "EncodedHex", sixgr.rrc.asn1.bitsToHex(payloadBits(:)));
end

function bits = localNormalizeBits(x)
if isempty(x)
    bits = int8([]);
    return;
end
x = x(:);
if all(x == 0 | x == 1)
    bits = int8(x);
    return;
end
bytes = uint8(x);
bits = zeros(numel(bytes) * 8, 1, "int8");
for i = 1:numel(bytes)
    for b = 1:8
        bits((i-1)*8+b) = int8(bitget(bytes(i), 9-b));
    end
end
end

function [value, next] = localExpectUInt(bits, pos, width, expected, name)
[value, next] = localReadUInt(bits, pos, width);
if value ~= expected
    error("sixgr:rrc:asn1:DecodeFailed", "Unexpected %s choice value %d.", name, value);
end
end

function [value, next] = localReadUInt(bits, pos, width)
if pos + width - 1 > numel(bits)
    error("sixgr:rrc:asn1:DecodeFailed", "SIB1 bitstream ended inside constrained integer.");
end
value = uint64(0);
for k = 1:width
    value = bitshift(value, 1) + uint64(bits(pos + k - 1) ~= 0);
end
value = double(value);
next = pos + width;
end

function [value, next] = localReadSigned(bits, pos, offset, width)
[raw, next] = localReadUInt(bits, pos, width);
value = double(raw) + double(offset);
end

function [text, next] = localReadDigits(bits, pos, count)
chars = repmat('0', 1, count);
next = pos;
for i = 1:count
    [digit, next] = localReadUInt(bits, next, 4);
    if digit > 9
        error("sixgr:rrc:asn1:DecodeFailed", "Invalid BCD digit in SIB1 PLMN.");
    end
    chars(i) = char('0' + digit);
end
text = string(chars);
end

function scs = localSCSFromIndex(idx, mode)
values = [15 30 60 120];
names = ["kHz15","kHz30","kHz60","kHz120"];
idx = double(idx) + 1;
if idx < 1 || idx > numel(values)
    error("sixgr:rrc:asn1:DecodeFailed", "Bad SCS enum in SIB1.");
end
if strcmpi(mode, "numeric")
    scs = values(idx);
else
    scs = names(idx);
end
end

function value = localPeriodicityFromIndex(idx)
names = ["ms5","ms10","ms20","ms40","ms80","ms160"];
idx = double(idx) + 1;
if idx < 1 || idx > numel(names)
    error("sixgr:rrc:asn1:DecodeFailed", "Bad SSB periodicity enum in SIB1.");
end
value = names(idx);
end

function value = localPreambleFormatFromIndex(idx)
names = ["0","1","2","3","A1","A2","A3","B4"];
idx = double(idx) + 1;
if idx < 1 || idx > numel(names)
    error("sixgr:rrc:asn1:DecodeFailed", "Bad PRACH preamble format enum in SIB1.");
end
value = names(idx);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
