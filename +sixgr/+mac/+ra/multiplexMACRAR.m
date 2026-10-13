function rar=multiplexMACRAR(responses)
% TS 38.321 6.1.5: a RAR MAC PDU contains one or more RAPID subPDUs.
% Each subPDU is independently encoded by encodeMACRAR; E links them.
assert(isstruct(responses) && ~isempty(responses), ...
    'sixgr:mac:ra:EmptyRARResponses','A RAR cannot be manufactured without a received preamble.');
assert(numel(unique([responses.RAPID]))==numel(responses), ...
    'sixgr:mac:ra:DuplicateRARRAPID','One RAR subPDU per detected RAPID.');
bytes=zeros(0,1,'uint8');
for k=1:numel(responses)
    r=responses(k);
    assert(isnan(r.BackoffIndicator) && numel(r.Bytes)==8, ...
        'sixgr:mac:ra:InvalidRARSubPDU','Multiplexing requires unpadded RAPID-only encoded subPDUs.');
    part=r.Bytes; part(1)=bitset(part(1),8,k<numel(responses));
    bytes=[bytes;part(:)]; %#ok<AGROW>
end
rar=responses(1); % Scalar compatibility fields identify only the first entry.
rar.Responses=responses; rar.Bytes=bytes;
rar.Bits=reshape(int8(bitget(repmat(bytes,1,8),repmat(8:-1:1,numel(bytes),1))).',[],1);
rar.BitLength=numel(rar.Bits);
rar.Hex=upper(string(reshape(dec2hex(bytes,2).',1,[])));
rar.PayloadHash=sixgr.rrc.asn1.asn1SHA256Hex(bytes);
end
