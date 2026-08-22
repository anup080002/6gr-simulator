function hash = hashTRSConfig(trsCfg)
%HASHTRSCONFIG Stable SHA-256 hash for strict TRS evidence.

S = trsCfg;
drop = {'ToolboxCarrier','ToolboxCSIRS','ConfigExport','StrictValidation','BaseConfig'};
drop = intersect(drop, fieldnames(S));
if ~isempty(drop)
    S = rmfield(S, drop);
end
txt = jsonencode(S);
hash = sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(txt, "UTF-8")));
end
