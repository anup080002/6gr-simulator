function tf = shouldRunProtocolComponentEvidence(cfg)
%SHOULDRUNPROTOCOLCOMPONENTEVIDENCE Resolve YAML authority for L2 evidence.
%   The configured protocol component campaign is enabled only when both
%   the protocol stack and its component-validation campaign are enabled.
%   Missing fields fail closed rather than silently manufacturing evidence.

arguments
    cfg (1, 1) struct
end

tf = logical(sixgr.util.structGet(cfg, "protocol.enabled", false)) && ...
    logical(sixgr.util.structGet(cfg, ...
    "protocol.component_validation.enabled", false));
end
