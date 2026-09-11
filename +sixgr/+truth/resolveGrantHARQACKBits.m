function bits=resolveGrantHARQACKBits(grant)
% Resolve HARQ-ACK aliases without converting arbitrary values to logical.
% A typed PUSCH payload owns HARQ separately from CSI; all populated legacy
% HARQ aliases must agree with it and with each other before any PHY work.
if ~isstruct(grant) || ~isscalar(grant)
    error('sixgr:truth:InvalidGrantUCIBits','UCI authority requires one grant struct.');
end
bits=int8(zeros(0,1)); established=false;
payload=sixgr.util.structGet(grant,'ExpectedUCIPayload',[]);
if ~isempty(payload)
    if ~isa(payload,'sixgr.phy.ul.pusch.PUSCHUCIPayload') || ~isscalar(payload)
        error('sixgr:truth:InvalidGrantExpectedUCIPayload', ...
            'ExpectedUCIPayload must be one immutable typed PUSCH UCI payload.');
    end
    bits=payload.HARQACK(:); established=true;
end
for name=["ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits"]
    raw=sixgr.util.structGet(grant,name,[]);
    if isempty(raw), continue; end
    value=localBits(raw,name);
    if isempty(value), continue; end % Unpopulated legacy aliases carry no authority.
    if established && ~isequal(bits,value)
        error('sixgr:truth:ConflictingGrantUCIBits', ...
            '%s conflicts with another HARQ-ACK alias or the typed PUSCH payload.',name);
    end
    bits=value; established=true;
end
end

function bits=localBits(raw,name)
if (isstring(raw) && isscalar(raw) && ~ismissing(raw)) || ...
        (ischar(raw) && isvector(raw))
    token=char(raw);
    if any(token(:)~='0' & token(:)~='1')
        error('sixgr:truth:InvalidGrantUCIBits','%s must contain only 0/1 bit characters.',name);
    end
    bits=int8(token(:)-'0');
elseif (isnumeric(raw) || islogical(raw)) && isreal(raw) && isvector(raw) && ...
        all(isfinite(raw(:))) && all(raw(:)==0 | raw(:)==1)
    bits=int8(raw(:));
else
    error('sixgr:truth:InvalidGrantUCIBits', ...
        '%s must be a finite real binary vector or one binary bit string before conversion.',name);
end
end
