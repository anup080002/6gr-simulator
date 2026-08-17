function configHash = hashResolvedScenario(resolved)
%HASHRESOLVEDSCENARIO SHA-256 identity of one fully resolved scenario.
%
% The hash is deliberately computed from the resolved structure rather
% than from a source YAML file.  Sweep-point overrides therefore receive
% identities distinct from their parent scenario.

if ~(isstruct(resolved) && isscalar(resolved))
    error("sixgr:lls6g:ConfigHashInputInvalid", ...
        "Resolved scenario hashing requires a scalar struct.");
end
try
    encoded = jsonencode(resolved);
    bytes = uint8(unicode2native(char(encoded), "UTF-8"));
    configHash = string(sixgr.util.sha256Hex(bytes));
catch cause
    error("sixgr:lls6g:ConfigHashUnavailable", ...
        "Unable to compute scenario config SHA-256 hash: %s", cause.message);
end
if ~isscalar(configHash) || ...
        isempty(regexp(char(configHash), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:lls6g:ConfigHashUnavailable", ...
        "Resolved scenario SHA-256 must contain 64 lowercase hexadecimal characters.");
end
end
