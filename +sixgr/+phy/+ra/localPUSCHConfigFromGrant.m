function pusch = localPUSCHConfigFromGrant(raCfg, grant)
%LOCALPUSCHCONFIGFROMGRANT Build PUSCH config from decoded RAR UL grant.
pusch = nrPUSCHConfig;
pusch.PRBSet = double(grant.PRBStart):(double(grant.PRBStart) + double(grant.NumPRB) - 1);
pusch.SymbolAllocation = [double(grant.SymbolStart) double(grant.NumSymbols)];
pusch.Modulation = char(string(grant.Modulation));
pusch.NumLayers = double(grant.NLayers);
pusch.RNTI = double(raCfg.TempCRNTI);
pusch.NID = double(raCfg.NCellID);
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
end
