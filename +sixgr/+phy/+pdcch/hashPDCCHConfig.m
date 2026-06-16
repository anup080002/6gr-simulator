function hash = hashPDCCHConfig(pdcchCfg)
%HASHPDCCHCONFIG Stable SHA-256 hash for strict PDCCH config evidence.

S = pdcchCfg;
drop = {'ToolboxCarrier','ToolboxPDCCH','ConfigExport','StrictValidation'};
drop = intersect(drop, fieldnames(S));
if ~isempty(drop)
    S = rmfield(S, drop);
end
txt = jsonencode(S);
hash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(txt, "UTF-8")));
end
