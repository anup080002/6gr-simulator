function hash = hashPRACHConfig(prachCfg)
%HASHPRACHCONFIG Stable SHA-256 hash for strict PRACH config evidence.

S = prachCfg;
% The digest identifies the resolved physical/statistical PRACH experiment.
% Runtime destinations and toolbox materializations are deliberately not
% part of that identity: relocating an otherwise identical run must not
% create a different scientific configuration hash.
drop = {'ToolboxCarrier','ToolboxPRACH','FirstActiveOccasion','ConfigExport', ...
    'ZCDPE','OutputDir','RunFolder'};
drop = intersect(drop, fieldnames(S));
if ~isempty(drop)
    S = rmfield(S, drop);
end
txt = jsonencode(S);
hash = sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(txt, "UTF-8")));
end
