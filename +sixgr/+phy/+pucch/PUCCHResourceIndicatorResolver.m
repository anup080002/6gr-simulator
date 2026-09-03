classdef PUCCHResourceIndicatorResolver
    %PUCCHRESOURCEINDICATORRESOLVER Exact PRI and set-0 CCE ownership.

    methods (Static)
        function result = resolveVector(row)
            setID = sixgr.phy.pucch.PUCCHUtil.number(row,"ResourceSetID");
            count = sixgr.phy.pucch.PUCCHUtil.number(row,"ResourceListSize");
            width = sixgr.phy.pucch.PUCCHUtil.number(row,"PRIFieldWidth");
            pri = sixgr.phy.pucch.PUCCHUtil.number(row,"PRIValue");
            firstCCE = sixgr.phy.pucch.PUCCHUtil.number(row,"FirstCCE");
            numCCE = sixgr.phy.pucch.PUCCHUtil.number(row,"NumCCE");
            formula = sixgr.phy.pucch.PUCCHUtil.truth( ...
                row,"RequiresSet0CCEFormula",false);
            result = struct("Valid",true,"Ordinal",NaN,"ErrorID","", ...
                "FormulaApplied",formula,"Operands",struct( ...
                "PRI",pri,"FirstCCE",firstCCE,"NumCCE",numCCE, ...
                "ResourceListSize",count,"PRIFieldWidth",width));
            scalarOperands = [setID,count,width,pri,firstCCE,numCCE];
            if any(~isfinite(scalarOperands)) || ...
                    setID < 0 || setID ~= fix(setID) || ...
                    count < 1 || count ~= fix(count) || ...
                    width < 0 || width > 3 || width ~= fix(width) || ...
                    pri < 0 || pri ~= fix(pri) || pri >= 2^width || ...
                    firstCCE < 0 || firstCCE ~= fix(firstCCE) || ...
                    numCCE <= 0 || numCCE ~= fix(numCCE)
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
                return;
            end
            if formula
                if setID ~= 0 || count <= 8 || firstCCE < 0 || ...
                        numCCE <= 0 || firstCCE >= numCCE
                    result.Valid = false;
                    result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
                    return;
                end
                cceTerm = floor(firstCCE * count / numCCE);
                result.Ordinal = mod(pri + cceTerm, count) + 1;
            elseif pri >= count
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
            else
                result.Ordinal = pri + 1;
            end
        end
    end
end
