function [bits, meta] = encodeSIB1UPER(msg)
%ENCODESIB1UPER Encode supported BCCH-DL-SCH/SIB1 profile into bits.
%
% The profile is intentionally constrained and bit-level deterministic. It
% carries the BCCH-DL-SCH -> c1 -> systemInformationBlockType1 choice and
% the SIB1 IEs required by the simulator anchor. Unsupported IEs fail closed
% in validateSIB1ForScenario.

sixgr.rrc.asn1.validateSIB1ForScenario(msg, struct());
sib1 = msg.message.c1.systemInformationBlockType1;
serv = sib1.servingCellConfigCommon;
dl = serv.downlinkConfigCommon;
ul = serv.uplinkConfigCommon;
plmn = sib1.cellAccessRelatedInfo.plmn_IdentityList(1);
pdcchSIB1 = dl.initialDownlinkBWP.pdcch_ConfigCommon.pdcch_ConfigSIB1;
prach = ul.initialUplinkBWP.rach_ConfigCommon;

body = [];
body = localAppendUInt(body, 0, 1); % BCCH-DL-SCH extension absent
body = localAppendUInt(body, 0, 1); % message.c1 selected
body = localAppendUInt(body, 0, 3); % c1.systemInformationBlockType1 index in anchor profile
body = localAppendUInt(body, 0, 1); % SIB1 extension absent
body = localAppendDigits(body, string(plmn.mcc), 3);
body = localAppendUInt(body, strlength(string(plmn.mnc)) == 3, 1);
body = localAppendDigits(body, string(plmn.mnc), strlength(string(plmn.mnc)));
body = localAppendUInt(body, double(sib1.cellAccessRelatedInfo.trackingAreaCode), 24);
body = localAppendUInt(body, double(sib1.cellAccessRelatedInfo.cellIdentity), 36);
body = localAppendUInt(body, strcmpi(string(sib1.cellAccessRelatedInfo.cellReservedForOperatorUse), "reserved"), 1);
body = localAppendSigned(body, double(sib1.cellSelectionInfo.q_RxLevMin), -140, 8);
body = localAppendSigned(body, double(sib1.cellSelectionInfo.q_QualMin), -43, 7);
body = localAppendUInt(body, localSCSIndex(dl.frequencyInfoDL.scs_SpecificCarrierList.subcarrierSpacing), 2);
body = localAppendUInt(body, double(dl.frequencyInfoDL.scs_SpecificCarrierList.carrierBandwidth), 10);
body = localAppendUInt(body, double(dl.frequencyInfoDL.absoluteFrequencySSB), 22);
body = localAppendUInt(body, double(dl.frequencyInfoDL.dl_AbsoluteFrequencyPointA), 22);
body = localAppendUInt(body, double(ul.frequencyInfoUL.absoluteFrequencyPointA), 22);
body = localAppendUInt(body, double(pdcchSIB1.controlResourceSetZero), 4);
body = localAppendUInt(body, double(pdcchSIB1.searchSpaceZero), 4);
body = localAppendUInt(body, double(serv.dmrs_TypeA_Position) - 2, 1);
body = localAppendUInt(body, localPeriodicityIndex(serv.ssb_periodicityServingCell), 3);
body = localAppendUInt(body, double(prach.configurationIndex), 8);
body = localAppendUInt(body, double(prach.rootSequenceIndex), 10);
body = localAppendUInt(body, double(prach.zeroCorrelationZoneConfig), 4);
body = localAppendUInt(body, double(prach.nPreambles), 7);
body = localAppendUInt(body, localPreambleFormatIndex(prach.preambleFormat), 3);

if numel(body) > 65535
    error("sixgr:rrc:asn1:SIB1TooLarge", "Encoded SIB1 anchor body exceeds 65535 bits.");
end
bits = [];
bits = localAppendUInt(bits, 1, 4); % anchor profile version
bits = localAppendUInt(bits, numel(body), 16);
bits = [bits, body]; %#ok<AGROW>
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits, zeros(1, pad)]; %#ok<AGROW>
end
bits = int8(bits(:));
meta = struct( ...
    "Profile", "sixgr_sib1_anchor_profile_v1", ...
    "ASN1Release", string(sixgr.util.structGet(msg, "asn1Release", "TS38331_anchor_profile_r2024a")), ...
    "PayloadBits", double(numel(bits)), ...
    "BodyBits", double(numel(body)), ...
    "PayloadHash", sixgr.rrc.asn1.sha256Hex(bits), ...
    "EncodedHex", sixgr.rrc.asn1.bitsToHex(bits));
end

function bits = localAppendDigits(bits, text, count)
chars = char(text);
if numel(chars) ~= double(count) || any(chars < '0' | chars > '9')
    error("sixgr:rrc:asn1:BadDigitString", "SIB1 digit string has invalid length/content.");
end
for i = 1:numel(chars)
    bits = localAppendUInt(bits, double(chars(i) - '0'), 4);
end
end

function bits = localAppendSigned(bits, value, offset, width)
enc = round(double(value) - double(offset));
bits = localAppendUInt(bits, enc, width);
end

function bits = localAppendUInt(bits, value, width)
value = round(double(value));
if ~(isfinite(value) && value >= 0 && value < 2^double(width))
    error("sixgr:rrc:asn1:ConstraintViolation", ...
        "Value %.12g cannot be encoded in %d bits.", value, width);
end
out = zeros(1, width);
for k = 1:width
    out(k) = bitget(uint64(value), width - k + 1);
end
bits = [bits, out]; %#ok<AGROW>
end

function idx = localSCSIndex(name)
switch string(name)
    case "kHz15"
        idx = 0;
    case "kHz30"
        idx = 1;
    case "kHz60"
        idx = 2;
    case "kHz120"
        idx = 3;
    otherwise
        error("sixgr:rrc:asn1:UnsupportedSIB1IE", "Unsupported SCS enum '%s'.", string(name));
end
end

function idx = localPeriodicityIndex(name)
names = ["ms5","ms10","ms20","ms40","ms80","ms160"];
idx = find(names == string(name), 1) - 1;
if isempty(idx)
    error("sixgr:rrc:asn1:UnsupportedSIB1IE", "Unsupported SSB periodicity '%s'.", string(name));
end
end

function idx = localPreambleFormatIndex(name)
names = ["0","1","2","3","A1","A2","A3","B4"];
idx = find(strcmpi(names, string(name)), 1) - 1;
if isempty(idx)
    error("sixgr:rrc:asn1:UnsupportedSIB1IE", "Unsupported PRACH preamble format '%s'.", string(name));
end
end
