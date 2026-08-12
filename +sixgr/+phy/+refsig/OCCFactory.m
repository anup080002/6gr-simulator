classdef OCCFactory
    %OCCFACTORY Normalized Walsh/Hadamard and DFT OCC matrices.

    methods (Static)
        function C = matrix(family,L)
            arguments
                family (1,1) string
                L (1,1) double {mustBePositive,mustBeInteger}
            end
            family = lower(strtrim(family));
            switch family
                case "walsh"
                    if 2^round(log2(L)) ~= L
                        error("sixgr:csi:InvalidWalshLength", ...
                            "Walsh OCC length must be a power of two; received %d.",L);
                    end
                    C = hadamard(L)/sqrt(L);
                case "dft"
                    n = (0:L-1).';
                    C = exp(-1j*2*pi*(n*n.')/L)/sqrt(L);
                otherwise
                    error("sixgr:csi:InvalidOCCFamily", ...
                        "OCC family must be walsh or dft; received '%s'.",family);
            end
        end

        function result = coupling(family,L,phaseDegPerChip)
            C = sixgr.phy.refsig.OCCFactory.matrix(family,L);
            phase = deg2rad(double(phaseDegPerChip))*(0:L-1).';
            A = C' * diag(exp(1j*phase)) * C;
            power = abs(A).^2;
            off = ~eye(L);
            offValues = power(off);
            result = struct("Matrix",A,"Power",power, ...
                "WorstLeakage",max(offValues), ...
                "MeanLeakage",mean(offValues), ...
                "P95Leakage",prctile(offValues,95), ...
                "TotalOffDiagonalEnergy",sum(offValues), ...
                "DiagonalPower",mean(diag(power)));
        end
    end
end
