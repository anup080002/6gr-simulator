function hash = hashPRACHConfig(prachCfg)
%HASHPRACHCONFIG Stable SHA-256 hash for strict PRACH config evidence.

S = prachCfg;
drop = {'ToolboxCarrier','ToolboxPRACH','FirstActiveOccasion','ConfigExport','ZCDPE'};
drop = intersect(drop, fieldnames(S));
if ~isempty(drop)
    S = rmfield(S, drop);
end
txt = jsonencode(S);
hash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(txt, "UTF-8")));
end
