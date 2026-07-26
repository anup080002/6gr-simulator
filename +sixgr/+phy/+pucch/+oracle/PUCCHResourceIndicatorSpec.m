classdef PUCCHResourceIndicatorSpec
    %PUCCHRESOURCEINDICATORSPEC Independent PRI/CCE ordinal formula.
    methods (Static)
        function out = resolve(setID,listSize,pri,width,firstCCE,numCCE,useCCE)
            limit=2^double(width);
            valid=all(isfinite(double([setID listSize pri width]))) && ...
                listSize>=1 && pri>=0 && pri<limit;
            if ~valid,ordinal=NaN;
            elseif logical(useCCE)
                ordinal=mod(floor(double(firstCCE)*double(listSize)/ ...
                    max(1,double(numCCE)))+double(pri),double(listSize))+1;
            else
                ordinal=mod(double(pri),double(listSize))+1;
            end
            out=struct("Ordinal",ordinal,"Valid",valid, ...
                "Metadata",sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHResourceIndicatorSpec"));
        end
    end
end
