function rar = encodeMACRAR(varargin)
%ENCODEMACRAR Build real MAC RAR bytes for a decoded PRACH RAPID.
%
% The payload follows the NR MAC RAR field ordering used for the strict
% anchor: 1 reserved bit, 12-bit TA command, 27-bit UL grant, 16-bit
% Temporary C-RNTI. The MAC subheader carries RAPID.

p = inputParser;
p.addParameter("RAPID", 0, @(x)isnumeric(x) && isscalar(x));
p.addParameter("TimingAdvanceCommand", 0, @(x)isnumeric(x) && isscalar(x));
p.addParameter("TemporaryCRNTI", 4660, @(x)isnumeric(x) && isscalar(x));
p.addParameter("ULGrant", struct(), @(x)isstruct(x));
p.addParameter("BackoffIndicator", NaN, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

rapid = localInteger(opt.RAPID, 0, 63, "RAPID");
ta = localInteger(opt.TimingAdvanceCommand, 0, 3846, "TimingAdvanceCommand");
tcRnti = localInteger(opt.TemporaryCRNTI, 1, 65519, "TemporaryCRNTI");
grant = opt.ULGrant;
if ~isfield(grant, "BitVector") || numel(grant.BitVector) ~= 27 || ...
        ~isreal(grant.BitVector) || any(~isfinite(grant.BitVector(:))) || ...
        any(grant.BitVector(:) ~= 0 & grant.BitVector(:) ~= 1)
    error("sixgr:mac:ra:InvalidULGrantBits", "MAC RAR requires a 27-bit UL grant.");
end

subheader = uint8(64 + rapid); % E=0, T=1, RAPID=rapid for single subPDU anchor.
payloadBits = int8([0; localIntToBits(ta, 12); int8(grant.BitVector(:)); localIntToBits(tcRnti, 16)]);
payloadBytes = localBitsToBytes(payloadBits);
bytes = [subheader; payloadBytes(:)];
if ~isnan(opt.BackoffIndicator)
    bi=localInteger(opt.BackoffIndicator,0,13,"BackoffIndicator");
    % E=1,T=0,R=R=0: a real leading BI subPDU, not metadata only.
    bytes=[uint8(128+bi);bytes];
end
bits = localBytesToBits(bytes);

rar = struct();
rar.RAPID = double(rapid);
rar.TimingAdvanceCommand = double(ta);
rar.TemporaryCRNTI = double(tcRnti);
rar.ULGrant = grant;
rar.ULGrantHex = string(grant.ULGrantHex);
rar.BackoffIndicator = double(opt.BackoffIndicator);
rar.Bytes = bytes(:);
rar.Bits = bits(:);
rar.BitLength = double(numel(bits));
rar.Hex = localBytesToHex(bytes);
rar.PayloadHash = sixgr.rrc.asn1.asn1SHA256Hex(bytes);
end

function value = localInteger(value, lo, hi, name)
if ~isreal(value) || ~isscalar(value) || ~isfinite(value) || ...
        value ~= fix(value) || value < lo || value > hi
    error("sixgr:mac:ra:InvalidMACRARField", "%s must be an integer in [%d,%d].", name, lo, hi);
end
value = double(value);
end

function bits = localIntToBits(value, nBits)
value = uint32(value);
bits = zeros(nBits, 1, "int8");
for ii = 1:nBits
    bits(ii) = int8(bitand(bitshift(value, -(nBits - ii)), 1));
end
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
bits = zeros(numel(bytes) * 8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii-1)*8 + jj) = int8(bitand(bitshift(bytes(ii), -(8-jj)), 1));
    end
end
end

function hex = localBytesToHex(bytes)
hex = upper(string(reshape(dec2hex(uint8(bytes(:)), 2).', 1, [])));
end
