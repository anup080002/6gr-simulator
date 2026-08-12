function [grid,audit] = normalizeEnergy(grid,referenceActiveRE,mode)
%NORMALIZEENERGY Apply explicit C0 structural-comparison normalization.
mode = lower(strtrim(string(mode)));
active = grid ~= 0;
nActive = nnz(active);
if nActive < 1
    error("sixgr:phy:ia:c0:waveform:EmptyGrid", ...
        "Cannot normalize an empty resource grid.");
end
before = sum(abs(grid(:)).^2);
switch mode
    case "equal_epre"
        scale = 1;
    case "equal_total_energy"
        scale = sqrt(double(referenceActiveRE)/double(nActive));
    case "equal_tf_resource"
        if double(referenceActiveRE) ~= double(nActive)
            error("sixgr:phy:ia:c0:waveform:UnequalTFResource", ...
                "equal_tf_resource requires identical active-RE counts in Phase 1.");
        end
        scale = 1;
    otherwise
        error("sixgr:phy:ia:c0:waveform:BadNormalization", ...
            "Unsupported normalization '%s'.",mode);
end
grid(active) = grid(active).*scale;
after = sum(abs(grid(:)).^2);
expected = before*scale^2;
closureDB = 10*log10(max(after,realmin)/max(expected,realmin));
audit = struct("Mode",mode,"ActiveRE",nActive,"Scale",scale, ...
    "EnergyBefore",before,"EnergyAfter",after,"ExpectedEnergy",expected, ...
    "ClosureDB",closureDB,"Passed",abs(closureDB)<0.01);
end
