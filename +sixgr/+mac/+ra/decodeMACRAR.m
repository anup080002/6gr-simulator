function rar = decodeMACRAR(bitsOrBytes, raCfg)
%DECODEMACRAR Decode MAC RAR bytes recovered from MSG2 DL-SCH.

if isempty(bitsOrBytes)
    error("sixgr:mac:ra:EmptyRAR", "Cannot decode empty MAC RAR.");
end
raw = bitsOrBytes(:);
if ~(isnumeric(raw) || islogical(raw)) || ~isreal(raw) || any(~isfinite(raw))
    error("sixgr:mac:ra:InvalidMACRARInput", "MAC RAR input must contain finite real bits or octets.");
end
if ~isa(raw,"uint8") && all(raw == 0 | raw == 1) && numel(raw) >= 8
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
if nargin < 2
    error("sixgr:mac:ra:MissingRARReceiverContext", ...
        "Interpreting decoded RAR fields requires the receiver's initial UL BWP and PUSCH common context.");
end
position=1; responses=struct([]); bi=NaN; backoff=0;
while true
    if position>numel(bytes)
        error('sixgr:mac:ra:UnsupportedMACRARSubheader','E=1 requires another complete MAC subPDU.');
    end
    header=bytes(position); more=bitand(header,uint8(128))~=0;
    if bitand(header,uint8(64))==0
        if position~=1 || ~isnan(bi) || bitand(header,uint8(48))~=0
            error('sixgr:mac:ra:InvalidMACRARField','BI must be first and its reserved bits must be zero.');
        end
        bi=double(bitand(header,uint8(15)));
        backoff=sixgr.mac.ra.rarBackoffMilliseconds(bi);
        position=position+1;
    else
        % This context is four-step CBRA. SI-request RAPID-only subPDUs
        % require the decoded SI-request resource context, not byte guessing.
        if position+7>numel(bytes)
            error('sixgr:mac:ra:ShortRAR','A CBRA RAPID subPDU requires seven payload octets.');
        end
        response=localDecodeResponse(bytes(position:position+7),raCfg);
        if ~isempty(responses) && any([responses.RAPID]==response.RAPID)
            error('sixgr:mac:ra:InvalidMACRARField','Duplicate RAPID responses are ambiguous.');
        end
        responses=[responses;response]; %#ok<AGROW>
        position=position+8;
    end
    if ~more, break; end
end
if isempty(responses)
    rar=struct('RAPID',NaN,'TimingAdvanceCommand',NaN,'TemporaryCRNTI',NaN, ...
        'ULGrant',struct(),'ULGrantHex',"");
else
    selected=find([responses.RAPID]==sixgr.util.structGet(raCfg,'PreambleIndex',NaN),1);
    if isempty(selected), selected=1; end
    rar=responses(selected);
end
rar.Responses=responses;
rar.BackoffIndicatorPresent=~isnan(bi);
rar.BackoffIndicator=bi;
rar.BackoffParameter_ms=backoff;
rar.Bytes=bytes(1:position-1);
rar.Bits=localBytesToBits(rar.Bytes);
rar.Hex=upper(string(reshape(dec2hex(rar.Bytes,2).',1,[])));
rar.PayloadHash=sixgr.rrc.asn1.asn1SHA256Hex(rar.Bytes);
rar.PaddingOctets=numel(bytes)-position+1;
end

function response=localDecodeResponse(bytes,raCfg)
rapid=double(bitand(bytes(1),uint8(63)));
payloadBits=localBytesToBits(bytes(2:8));
ta=localBitsToInt(payloadBits(2:13));
grantBits=int8(payloadBits(14:40));
tcRnti=localBitsToInt(payloadBits(41:56));
if payloadBits(1)~=0 || ta>3846 || tcRnti<1 || tcRnti>65519
    error('sixgr:mac:ra:InvalidMACRARField','Reserved bit, TA command, or Temporary C-RNTI is invalid.');
end
grant=sixgr.mac.ra.RARULGrantCodec.decode(grantBits,raCfg);
grant.TemporaryCRNTI=double(tcRnti);
response=struct('RAPID',rapid,'TimingAdvanceCommand',ta,'TemporaryCRNTI',tcRnti, ...
    'ULGrant',grant,'ULGrantHex',sixgr.rrc.asn1.bitsToHex(grantBits));
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
