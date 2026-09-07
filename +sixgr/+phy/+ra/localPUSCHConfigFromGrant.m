function pusch = localPUSCHConfigFromGrant(raCfg, grant)
%LOCALPUSCHCONFIGFROMGRANT Build PUSCH config from decoded RAR UL grant.
pusch = nrPUSCHConfig;
pusch.PRBSet = double(grant.PRBStart):(double(grant.PRBStart) + double(grant.NumPRB) - 1);
pusch.SymbolAllocation = [double(grant.SymbolStart) double(grant.NumSymbols)];
pusch.MappingType = char(string(sixgr.util.structGet(grant, "MappingType", "A")));
pusch.Modulation = char(string(grant.Modulation));
pusch.NumLayers = double(grant.NLayers);
pusch.RNTI = double(raCfg.TempCRNTI);
pusch.NID = double(raCfg.NCellID);
% The decoded rank-one RA UL grant owns logical port zero explicitly.  The
% PT-RS association below must bind to that scheduled DM-RS port rather
% than relying on an nrPUSCHConfig default.
pusch.DMRS.DMRSPortSet = 0;
% A rejected waveform setting must abort this grant, not leave a Toolbox
% default in place while the grant/evidence claims the requested setting.
pusch.DMRS.DMRSAdditionalPosition = 2;
pusch.TransformPrecoding = localLogical(grant.TransformPrecoding, "TransformPrecoding");
pusch.EnablePTRS = localLogical(sixgr.util.structGet(grant, ...
    "EnablePTRS", sixgr.util.structGet(raCfg, ...
    "Msg3PUSCH.EnablePTRS", false)), "EnablePTRS");
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

function value = localLogical(value, name)
if ~(isnumeric(value) || islogical(value)) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value) || ~ismember(value, [0 1])
    error("sixgr:phy:ra:InvalidPUSCHWaveformFlag", ...
        "%s must be an explicit logical scalar or numeric 0/1.", name);
end
value = logical(value);
end
