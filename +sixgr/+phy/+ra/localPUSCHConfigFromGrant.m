function pusch = localPUSCHConfigFromGrant(raCfg, grant)
%LOCALPUSCHCONFIGFROMGRANT Build PUSCH config from decoded RAR UL grant.
pusch = nrPUSCHConfig;
pusch.PRBSet = double(grant.PRBStart):(double(grant.PRBStart) + double(grant.NumPRB) - 1);
pusch.SymbolAllocation = [double(grant.SymbolStart) double(grant.NumSymbols)];
pusch.Modulation = char(string(grant.Modulation));
pusch.NumLayers = double(grant.NLayers);
pusch.RNTI = double(raCfg.TempCRNTI);
pusch.NID = double(raCfg.NCellID);
% The decoded rank-one RA UL grant owns logical port zero explicitly.  The
% PT-RS association below must bind to that scheduled DM-RS port rather
% than relying on an nrPUSCHConfig default.
pusch.DMRS.DMRSPortSet = 0;
try
    pusch.DMRS.DMRSAdditionalPosition = 2;
catch
end
try
    pusch.TransformPrecoding = logical(grant.TransformPrecoding);
catch
end
try
    pusch.EnablePTRS = logical(sixgr.util.structGet(grant, ...
        "EnablePTRS", sixgr.util.structGet(raCfg, ...
        "Msg3PUSCH.EnablePTRS", false)));
catch
end
if logical(pusch.EnablePTRS)
    pusch.PTRS.PTRSPortSet = double(sixgr.util.structGet(grant, ...
        "PTRSPortSet", sixgr.util.structGet(raCfg, ...
        "Msg3PUSCH.PTRSPortSet", 0)));
    pusch.PTRS.TimeDensity = double(sixgr.util.structGet(grant, ...
        "PTRSTimeDensity", sixgr.util.structGet(raCfg, ...
        "Msg3PUSCH.PTRSTimeDensity", 1)));
    pusch.PTRS.FrequencyDensity = double(sixgr.util.structGet(grant, ...
        "PTRSFrequencyDensity", sixgr.util.structGet(raCfg, ...
        "Msg3PUSCH.PTRSFrequencyDensity", 2)));
    pusch.PTRS.REOffset = char(string(sixgr.util.structGet(grant, ...
        "PTRSREOffset", sixgr.util.structGet(raCfg, ...
        "Msg3PUSCH.PTRSREOffset", "00"))));
end
end
