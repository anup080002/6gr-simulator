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
            declaredFormula = sixgr.phy.pucch.PUCCHUtil.truth( ...
                row,"RequiresSet0CCEFormula",false);
            formula = setID==0 && count>8;
            result = struct("Valid",true,"Ordinal",NaN,"ErrorID","", ...
                "FormulaApplied",formula,"Operands",struct( ...
                "PRI",pri,"FirstCCE",firstCCE,"NumCCE",numCCE, ...
                "ResourceListSize",count,"PRIFieldWidth",width));
            scalarOperands = [setID,count,width,pri];
            if any(~isfinite(scalarOperands)) || ...
                    setID < 0 || setID ~= fix(setID) || ...
                    count < 1 || count ~= fix(count) || ...
                    width < 0 || width > 3 || width ~= fix(width) || ...
                    pri < 0 || pri ~= fix(pri) || pri >= 2^width || ...
                    declaredFormula~=formula
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
                return;
            end
            if formula
                if ~isfinite(firstCCE) || ~isfinite(numCCE) || ...
                        firstCCE<0 || firstCCE~=fix(firstCCE) || ...
                        numCCE<=0 || numCCE~=fix(numCCE) || firstCCE>=numCCE
                    result.Valid = false;
                    result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
                    return;
                end
                % TS 38.213 v18.8.0, 9.2.3: eight PRI groups, with
                % R mod 8 larger groups first. n_CCE selects within the
                % indicated group; it is NOT an offset modulo the full list.
                remainder = mod(count,8);
                if pri<remainder
                    groupSize = ceil(count/8);
                    index0 = floor(firstCCE*groupSize/numCCE)+pri*groupSize;
                else
                    groupSize = floor(count/8);
                    index0 = floor(firstCCE*groupSize/numCCE)+pri*groupSize+remainder;
                end
                result.Ordinal = index0+1;
            elseif pri >= count
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidResourceIndicator";
            else
                result.Ordinal = pri + 1;
            end
        end
    end
end
