function rar = decodeMACRAR(bitsOrBytes, raCfg)
%DECODEMACRAR Decode MAC RAR bytes recovered from MSG2 DL-SCH.

if isempty(bitsOrBytes)
    error("sixgr:mac:ra:EmptyRAR", "Cannot decode empty MAC RAR.");
end
raw = bitsOrBytes(:);
if ~(isnumeric(raw) || islogical(raw)) || ~isreal(raw) || any(~isfinite(raw))
    error("sixgr:mac:ra:InvalidMACRARInput", "MAC RAR input must contain finite real bits or octets.");
end
if ~isa(raw,"uint8") && all(raw == 0 | raw == 1) && numel(raw) > 8
    if mod(numel(raw),8) ~= 0
        error("sixgr:mac:ra:InvalidMACRARInput", "MAC RAR bit input must contain complete octets.");
    end
    bytes = localBitsToBytes(int8(raw));
else
    if any(raw < 0 | raw > 255 | raw ~= fix(raw)) || isa(raw,"int8")
        error("sixgr:mac:ra:InvalidMACRARInput", "MAC RAR octets must be integers in [0,255]; int8 input is a bit vector.");
    end
    bytes = uint8(raw);
end
if numel(bytes) < 8
    error("sixgr:mac:ra:ShortRAR", "MAC RAR requires at least 8 octets in the anchor profile.");
end

subheader = bytes(1);
if bitand(subheader,uint8(192)) ~= 64
    error("sixgr:mac:ra:UnsupportedMACRARSubheader", ...
        "This parser requires one E=0,T=1 RAPID subPDU; BI and multiple RAR subPDUs are not silently reinterpreted.");
end
rapid = double(bitand(subheader, uint8(63)));
payloadBits = localBytesToBits(bytes(2:8));
ta = localBitsToInt(payloadBits(2:13));
grantBits = int8(payloadBits(14:40));
tcRnti = localBitsToInt(payloadBits(41:56));
if payloadBits(1) ~= 0 || ta > 3846 || tcRnti < 1 || tcRnti > 65519
    error("sixgr:mac:ra:InvalidMACRARField", "Reserved bit, TA command, or Temporary C-RNTI is invalid.");
end
if nargin < 2
    error("sixgr:mac:ra:MissingRARReceiverContext", ...
        "Interpreting decoded RAR fields requires the receiver's initial UL BWP and PUSCH common context.");
end
grant = sixgr.mac.ra.RARULGrantCodec.decode(grantBits, raCfg);
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
rar.PayloadHash = sixgr.rrc.asn1.asn1SHA256Hex(bytes(1:8));
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
