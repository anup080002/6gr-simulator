function hash = hashPDCCHConfig(pdcchCfg)
%HASHPDCCHCONFIG Stable SHA-256 hash for strict PDCCH config evidence.

S = pdcchCfg;
% Hash only the canonical, serializable PDCCH assignment.  BaseConfig and
% toolbox/runtime objects are execution context, may contain complex-valued
% MIMO precoders, and are already represented by the explicit carrier,
% CORESET, search-space, DCI-size and context-digest fields retained here.
% Including those runtime objects made an otherwise valid rank-2 scenario
% fail in jsonencode and also made the digest depend on unrelated PHY state.
drop = {'ToolboxCarrier','ToolboxCORESET','ToolboxSearchSpace','ToolboxPDCCH', ...
    'CORESETDefinition','SearchSpaceDefinition','DCIContext','DCIContexts', ...
    'BaseConfig','ConfigExport','StrictValidation','ConfigHash'};
drop = intersect(drop, fieldnames(S));
if ~isempty(drop)
    S = rmfield(S, drop);
end
txt = jsonencode(S);
hash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(txt, "UTF-8")));
end
