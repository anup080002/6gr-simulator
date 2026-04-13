function [tbsBits, upperBoundBits] = resolveGrantTBSBits(grant, sourceLabel)
%RESOLVEGRANTTBSBITS Resolve and validate a physically meaningful grant TBS.

arguments
    grant (1,1) struct
    sourceLabel = "grant"
end

sourceLabel = string(sourceLabel);

if isfield(grant, "TBSBits") && ~isempty(grant.TBSBits)
    tbsBits = round(double(grant.TBSBits));
elseif isfield(grant, "TBSBytes") && ~isempty(grant.TBSBytes)
    tbsBits = round(8 * double(grant.TBSBytes));
else
    error("sixgr:GrantTBS:MissingValue", ...
        "%s has no TBSBits or TBSBytes field.", char(sourceLabel));
end

if ~isfinite(tbsBits) || tbsBits < 0
    error("sixgr:GrantTBS:InvalidValue", ...
        "%s has a non-finite or negative TBSBits value.", char(sourceLabel));
end

if tbsBits > 0 && mod(tbsBits, 8) ~= 0
    error("sixgr:GrantTBS:NotByteAligned", ...
        "%s has non-byte-aligned TBSBits=%d.", char(sourceLabel), round(tbsBits));
end

if isfield(grant, "TBSBytes") && ~isempty(grant.TBSBytes)
    tbsBytes = round(double(grant.TBSBytes));
    if ~isfinite(tbsBytes) || tbsBytes < 0
        error("sixgr:GrantTBS:InvalidBytes", ...
            "%s has a non-finite or negative TBSBytes value.", char(sourceLabel));
    end
    if tbsBits ~= 8 * tbsBytes
        error("sixgr:GrantTBS:BitsBytesMismatch", ...
            "%s has inconsistent TBSBits=%d and TBSBytes=%d.", ...
            char(sourceLabel), round(tbsBits), round(tbsBytes));
    end
end

upperBoundBits = sixgr.util.grantTBSUpperBoundBits(grant);
if isfinite(upperBoundBits) && upperBoundBits > 0 && tbsBits > upperBoundBits
    error("sixgr:GrantTBS:ImpossibleValue", ...
        "%s has TBSBits=%d above loose upper bound %d.", ...
        char(sourceLabel), round(tbsBits), round(upperBoundBits));
end
end
