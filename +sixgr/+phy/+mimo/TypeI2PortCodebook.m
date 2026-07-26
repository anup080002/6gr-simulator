classdef TypeI2PortCodebook
    %TYPEI2PORTCODEBOOK Exact TS 38.214 two-port Type-I floor.

    methods (Static)
        function candidates = enumerate(rankValue)
            arguments
                rankValue (1,1) double {mustBeInteger,mustBePositive}
            end
            switch rankValue
                case 1
                    phase = [1, 1i, -1, -1i];
                    candidates = complex(zeros(2,1,4));
                    for index = 1:4
                        candidates(:,:,index) = [1; phase(index)] / sqrt(2);
                    end
                case 2
                    phase = [1, 1i];
                    candidates = complex(zeros(2,2,2));
                    for index = 1:2
                        candidates(:,:,index) = [1 1; phase(index) -phase(index)] / 2;
                    end
                otherwise
                    error("sixgr:mimo:UnsupportedRank", ...
                        "The two-port Type-I codebook supports rank 1 or 2.");
            end
        end

        function W = matrix(rankValue, zeroBasedIndex)
            candidates = sixgr.phy.mimo.TypeI2PortCodebook.enumerate(rankValue);
            index = double(zeroBasedIndex) + 1;
            if ~(isscalar(index) && isfinite(index) && index == round(index) && ...
                    index >= 1 && index <= size(candidates,3))
                error("sixgr:mimo:InvalidPMI", ...
                    "PMI %s is outside the two-port rank-%d domain.", ...
                    mat2str(zeroBasedIndex), rankValue);
            end
            W = candidates(:,:,index);
        end
    end
end
