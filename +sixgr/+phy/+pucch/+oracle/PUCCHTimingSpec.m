classdef PUCCHTimingSpec
    %PUCCHTIMINGSPEC Independent K1 and TDD ownership check.
    methods (Static)
        function out = resolve(pdschEnd,k1,ownership,startSymbol,numSymbols)
            due=double(pdschEnd)+double(k1);
            token=char(string(ownership));
            range=double(startSymbol)+(1:double(numSymbols));
            legal=all(range>=1 & range<=numel(token)) && ...
                all(token(range)=='U');
            out=struct("DueSlot",due,"Legal",logical(legal), ...
                "SymbolShiftApplied",false,"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHTimingSpec"));
        end
    end
end
