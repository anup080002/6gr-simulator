function offset = type0GSCNOffset(frequencyRange, kSSB, combinedIndex)
%TYPE0GSCNOFFSET Resolve the absent-CORESET indication GSCN offset.
%
% This implements TS 38.213 V18.8.0 Tables 13-16 and 13-17. It is
% deliberately separate from ordinary valid CORESET0 table resolution.

fr = upper(strtrim(string(frequencyRange)));
kSSB = double(kSSB);
combinedIndex = double(combinedIndex);
if ~(isscalar(kSSB) && isfinite(kSSB) && kSSB == fix(kSSB)) || ...
        ~(isscalar(combinedIndex) && isfinite(combinedIndex) && ...
        combinedIndex >= 0 && combinedIndex <= 255 && ...
        combinedIndex == fix(combinedIndex))
    error("sixgr:phy:pdcch:type0_context_not_supported", ...
        "kSSB and combined pdcch-ConfigSIB1 index must be integers.");
end

switch fr
    case "FR1"
        if kSSB >= 24 && kSSB <= 26
            offset = 256 * (kSSB - 24) + combinedIndex + 1;
        elseif kSSB >= 27 && kSSB <= 29
            offset = -(256 * (kSSB - 27) + combinedIndex + 1);
        else
            error("sixgr:phy:pdcch:no_type0_coreset_in_gscn_range", ...
                "FR1 kSSB=%g has no associated Type-0 CORESET GSCN offset.", ...
                kSSB);
        end
    case "FR2"
        if kSSB == 12
            offset = combinedIndex + 1;
        elseif kSSB == 13
            offset = -(combinedIndex + 1);
        else
            error("sixgr:phy:pdcch:no_type0_coreset_in_gscn_range", ...
                "FR2 kSSB=%g has no associated Type-0 CORESET GSCN offset.", ...
                kSSB);
        end
    otherwise
        error("sixgr:phy:pdcch:type0_context_not_supported", ...
            "Frequency range %s is unsupported.", fr);
end
end
