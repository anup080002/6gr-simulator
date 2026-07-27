classdef ParsevalLedger
    %PARSEVALLEDGER Exact unitary-transform energy reconciliation.
    methods (Static)
        function row=verify(grid,usefulSamples)
            ge=sum(abs(double(grid(:))).^2);
            ue=sum(abs(double(usefulSamples(:))).^2);
            relative=abs(ge-ue)/max(ge,eps);
            row=struct("GridEnergy",ge,"UsefulSampleEnergy",ue, ...
                "ScaleFactor",1,"RelativeError",relative, ...
                "Status",string(relative<=1e-10));
            if relative>1e-10
                error("WAVEFORM:PowerLedgerMismatch", ...
                    "Unitary Parseval error %.3g exceeds 1e-10.",relative);
            end
        end
    end
end
