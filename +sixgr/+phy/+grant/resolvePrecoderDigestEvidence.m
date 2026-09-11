function evidence = resolvePrecoderDigestEvidence(grant, precodeInfo)
%RESOLVEPRECODERDIGESTEVIDENCE Bind frozen and applied waveform precoders.
%
% RequestedPrecoderSHA256 and AppliedPrecoderSHA256 deliberately refer to
% the same waveform-domain matrix contract.  The logical codebook matrix
% selected by PMI/TPMI is not interchangeable with the physical element-
% domain matrix produced after hybrid RF/baseband expansion.

arguments
    grant (1,1) struct = struct()
    precodeInfo (1,1) struct = struct()
end

frozen = sixgr.util.structGet(grant, "PHYGrant.PrecodingState", ...
    sixgr.util.structGet(grant, "PrecodingState", struct()));

requested = localFirstDigest( ...
    sixgr.util.structGet(frozen, "AppliedMatrixSHA256", ""), ...
    sixgr.util.structGet(grant, "RequestedPrecoderSHA256", ""));
applied = localFirstDigest( ...
    sixgr.util.structGet(precodeInfo, "AppliedMatrixSHA256", ""));

matrix = sixgr.util.structGet(precodeInfo, "MatrixPorts", ...
    sixgr.util.structGet(precodeInfo, "Matrix", []));
if ~isempty(matrix)
    applied = string(sixgr.phy.mimo.MatrixContract.digest(double(matrix)));
end

domain = localFirstText( ...
    sixgr.util.structGet(frozen, "WaveformDomain", ""), ...
    sixgr.util.structGet(precodeInfo, "WaveformDomain", ""), ...
    localDomainFromPrecoder(precodeInfo));
contextId = localFirstText( ...
    sixgr.util.structGet(grant, "PHYGrant.GrantContextId", ""), ...
    sixgr.util.structGet(grant, "PHYGrantContextId", ""), ...
    sixgr.util.structGet(grant, "GrantContextId", ""));

localValidateDigest(requested, "requested");
localValidateDigest(applied, "applied");
if strlength(requested) > 0 && strlength(applied) > 0 && ...
        strlength(strtrim(domain)) == 0
    error("sixgr:phy:grant:MissingPrecoderDigestDomain", ...
        "Frozen/applied precoder digests require an explicit waveform domain.");
end

evidence = struct( ...
    "RequestedPrecoderSHA256", requested, ...
    "AppliedPrecoderSHA256", applied, ...
    "AppliedPrecoderMatrixSHA256", applied, ...
    "PrecoderDigestDomain", domain, ...
    "FrozenGrantContextId", contextId);
end

function value = localFirstDigest(varargin)
value = "";
for index = 1:nargin
    candidate = lower(strtrim(string(varargin{index})));
    candidate = candidate(strlength(candidate) > 0);
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function value = localFirstText(varargin)
value = "";
for index = 1:nargin
    candidate = strtrim(string(varargin{index}));
    candidate = candidate(strlength(candidate) > 0);
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function value = localDomainFromPrecoder(precodeInfo)
if logical(sixgr.util.structGet(precodeInfo, "HybridElementDomainApplied", false))
    value = "physical_element";
else
    value = "logical_antenna_port";
end
end

function localValidateDigest(value, label)
if strlength(value) == 0
    return;
end
if isempty(regexp(char(value), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:phy:grant:InvalidPrecoderDigest", ...
        "%s precoder SHA-256 is not a lowercase 64-hex digest.", label);
end
end
