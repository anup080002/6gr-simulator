function hash = hashSRSConfig(srsCfg)
%HASHSRSCONFIG Deterministic SHA-256 hash for strict SRS config.

fields = ["RunId","ScenarioName","CellId","UEId","NCellID","NSizeGrid", ...
    "NStartGrid","SubcarrierSpacingKHz","ResourceSetUsage","ResourceType", ...
    "Periodicity","Offset","ResourceIds","NumSRSPorts","SymbolStart", ...
    "NumSRSSymbols","RepetitionFactor","CombNumber","CombOffset", ...
    "CyclicShift","SequenceId","FrequencyPosition","FrequencyShift", ...
    "BHOP","BHop","C_SRS","B_SRS","CoverageRequirement", ...
    "FullCarrierSoundingRequired"];
parts = strings(0, 1);
for ii = 1:numel(fields)
    f = char(fields(ii));
    if isfield(srsCfg, f)
        parts(end+1, 1) = string(f) + "=" + localValueString(srsCfg.(f)); %#ok<AGROW>
    end
end
hash = string(sixgr.rrc.asn1.sha256Hex(uint8(char(strjoin(parts, ";")))));
end

function txt = localValueString(v)
if isnumeric(v) || islogical(v)
    txt = strjoin(string(double(v(:))).', ",");
else
    txt = strjoin(string(v(:)).', ",");
end
end
