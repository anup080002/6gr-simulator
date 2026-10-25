function outcome=broadcastBCHBlockOutcome(rec)
%BROADCASTBCHBLOCKOUTCOME One completed original BCH block, not SI procedure.
% Integrity checks do not independently authenticate execution. The original
% PBCH receiver owns these returned operands. No denominator is invented for
% skipped, uncompleted, historical or malformed evidence.
outcome=struct('Eligible',false,'BlockError',NaN,'Source',"unavailable", ...
    'Status',"missing_original_completed_BCH_evidence");
id='sixgr:link:InvalidBCHBlockEvidence';
assert(isstruct(rec)&&isscalar(rec),id,'Require an original scalar receiver result.');
required={'DecodeAttempted','BCHCRCValid','BCHTransportBlockNumBits', ...
    'BCHTransportBlockHex','BCHTransportBlockHash'};
if ~all(isfield(rec,required)), return; end
assert(islogical(rec.DecodeAttempted)&&isscalar(rec.DecodeAttempted),id, ...
    'Preserve the original logical decode-attempt flag.');
if isnumeric(rec.BCHCRCValid)&&isreal(rec.BCHCRCValid)&&isscalar(rec.BCHCRCValid)&&isnan(rec.BCHCRCValid)
    outcome.Status="unavailable_original_BCH_CRC"; return;
end
assert(islogical(rec.BCHCRCValid)&&isscalar(rec.BCHCRCValid),id, ...
    'Preserve the original logical BCH CRC, not a numeric cast.');
n=rec.BCHTransportBlockNumBits;
assert(isnumeric(n)&&isreal(n)&&isscalar(n),id,'Require original scalar numeric BCH bit count.');
if isnan(n), outcome.Status="missing_original_completed_BCH_evidence"; return; end
assert(isfinite(n)&&n==24,id,'A returned NR BCH transport block must contain 24 bits.');
[hex,validHex]=localText(rec.BCHTransportBlockHex);
[hash,validHash]=localText(rec.BCHTransportBlockHash);
assert(validHex&&validHash,id,'Original block hex/hash must be scalar text.');
if strlength(hex)==0 || strlength(hash)==0, return; end
assert(~isempty(regexp(char(hex),'^[0-9a-fA-F]{6}$','once'))&& ...
    ~isempty(regexp(char(hash),'^[0-9a-fA-F]{64}$','once')),id,'Malformed original block hex/hash.');
assert(rec.DecodeAttempted,id,'A returned block contradicts a declared unattempted decode.');
% bitsToHex is MSB-first, byte packed. The original hash is over the 24
% uint8 bit values, NOT over the three packed bytes or hexadecimal text.
bytes=uint8(sscanf(char(hex),'%2x'));
bits=zeros(24,1,'uint8');
for k=1:3
    bits((k-1)*8+(1:8))=uint8(bitget(bytes(k),8:-1:1));
end
expected=string(sixgr.rrc.asn1.asn1SHA256Hex(bits));
assert(strcmpi(hash,expected),id,'Original BCH block bytes and returned hash disagree.');
outcome.Eligible=true;
outcome.BlockError=double(~rec.BCHCRCValid);
outcome.Source="original_completed_BCH_decode_raw_CRC";
outcome.Status="one_original_BCH_block_not_combined_SI_procedure";
end

function [text,valid]=localText(raw)
valid=(isstring(raw)&&isscalar(raw)&&~ismissing(raw)) || (ischar(raw)&&isrow(raw));
text="";
if valid, text=string(raw); end
end
