classdef AbsoluteRadioTime
    %ABSOLUTERADIOTIME Exact slot/symbol conversion for one numerology.

    properties (SetAccess=immutable)
        Mu (1,1) double
        SlotsPerFrame (1,1) double
        SymbolsPerSlot (1,1) double
        AbsoluteSlot (1,1) double
        SymbolInSlot (1,1) double
        AbsoluteSymbol (1,1) double
    end

    methods
        function obj = AbsoluteRadioTime(mu, absoluteSlot, symbolInSlot, symbolsPerSlot)
            arguments
                mu (1,1) double {mustBeInteger,mustBeNonnegative}
                absoluteSlot (1,1) double {mustBeInteger,mustBeNonnegative}
                symbolInSlot (1,1) double {mustBeInteger,mustBeNonnegative}
                symbolsPerSlot (1,1) double {mustBeInteger,mustBePositive} = 14
            end
            if symbolInSlot >= symbolsPerSlot
                error("sixgr:mac:InvalidAbsoluteRadioTime", ...
                    "SymbolInSlot must be smaller than SymbolsPerSlot.");
            end
            obj.Mu=mu; obj.SlotsPerFrame=10*2^mu;
            obj.SymbolsPerSlot=symbolsPerSlot;
            obj.AbsoluteSlot=absoluteSlot; obj.SymbolInSlot=symbolInSlot;
            obj.AbsoluteSymbol=absoluteSlot*symbolsPerSlot+symbolInSlot;
        end
    end
end
