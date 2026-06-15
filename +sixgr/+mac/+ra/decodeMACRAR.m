function rar = decodeMACRAR(bitsOrBytes)
%DECODEMACRAR Decode MAC RAR bytes recovered from MSG2 DL-SCH.

if isempty(bitsOrBytes)
    error("sixgr:mac:ra:EmptyRAR", "Cannot decode empty MAC RAR.");
end
raw = bitsOrBytes(:);
if all(raw == 0 | raw == 1) && numel(raw) > 8
    bytes = localBitsToBytes(int8(raw));
else
    bytes = uint8(raw);
end
if numel(bytes) < 8
    error("sixgr:mac:ra:ShortRAR", "MAC RAR requires at least 8 octets in the anchor profile.");
end

subheader = bytes(1);
rapid = double(bitand(subheader, uint8(63)));
payloadBits = localBytesToBits(bytes(2:8));
ta = localBitsToInt(payloadBits(2:13));
grantBits = int8(payloadBits(14:40));
tcRnti = localBitsToInt(payloadBits(41:56));
grant = localDecodeGrant(grantBits);
grant.TemporaryCRNTI = double(tcRnti);

rar = struct();
rar.RAPID = double(rapid);
rar.TimingAdvanceCommand = double(ta);
rar.TemporaryCRNTI = double(tcRnti);
rar.ULGrant = grant;
rar.ULGrantHex = sixgr.rrc.asn1.bitsToHex(grantBits);
rar.Bytes = bytes(1:8);
rar.Bits = localBytesToBits(bytes(1:8));
rar.Hex = upper(string(reshape(dec2hex(bytes(1:8), 2).', 1, [])));
rar.PayloadHash = sixgr.rrc.asn1.sha256Hex(bytes(1:8));
end

function grant = localDecodeGrant(bits)
bits = int8(bits(:) ~= 0);
freqAssignment = localBitsToInt(bits(2:11));
prbStart = floor(freqAssignment / 32);
numPRB = mod(freqAssignment, 32);
if numPRB < 1
    numPRB = 1;
end
timeAssignment = localBitsToInt(bits(12:15));
mcs = localBitsToInt(bits(16:20));
tpc = localBitsToInt(bits(21:23));
grant = struct();
grant.FrequencyHoppingFlag = logical(bits(1));
grant.FrequencyAssignment = double(freqAssignment);
grant.PRBStart = double(prbStart);
grant.NumPRB = double(numPRB);
grant.TimeResourceAssignment = double(timeAssignment);
grant.SymbolStart = 0;
grant.NumSymbols = 14;
grant.MCS = double(mcs);
grant.Modulation = "QPSK";
grant.TargetCodeRate = 120/1024;
grant.TPCCommand = double(tpc);
grant.CSIRequest = logical(bits(24));
grant.TransformPrecoding = logical(bits(25));
grant.RV = 0;
grant.NLayers = 1;
grant.BitVector = bits;
grant.ULGrantHex = sixgr.rrc.asn1.bitsToHex(bits);
grant.Valid = true;
grant.ValidationStatus = "OK";
end

function bytes = localBitsToBytes(bits)
bits = int8(bits(:) ~= 0);
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
bytes = zeros(numel(bits)/8, 1, "uint8");
for ii = 1:numel(bytes)
    v = uint8(0);
    for jj = 1:8
        v = bitor(bitshift(v, 1), uint8(bits((ii-1)*8 + jj)));
    end
    bytes(ii) = v;
end
end

function bits = localBytesToBits(bytes)
bytes = uint8(bytes(:));
bits = zeros(numel(bytes)*8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii-1)*8 + jj) = int8(bitand(bitshift(bytes(ii), -(8-jj)), 1));
    end
end
end

function value = localBitsToInt(bits)
value = 0;
bits = int8(bits(:) ~= 0);
for ii = 1:numel(bits)
    value = value * 2 + double(bits(ii));
end
end
