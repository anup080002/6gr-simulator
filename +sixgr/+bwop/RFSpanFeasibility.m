classdef RFSpanFeasibility
    %RFSPANFEASIBILITY Deterministic carrier, guard, SSB and RF-span checks.

    methods (Static)
        function out = evaluate(startRB,sizeRB,carrierRB,rfStartRB,rfSizeRB,guardRB,ssbStartRB,ssbSizeRB)
            values=double([startRB sizeRB carrierRB rfStartRB rfSizeRB guardRB ssbStartRB ssbSizeRB]);
            if any(~isfinite(values))||any(values~=round(values))||sizeRB<1||carrierRB<1||rfSizeRB<1||guardRB<0||ssbSizeRB<1
                error("sixgr:bwop:InvalidRegionGeometry", ...
                    "Region and RF-span values must be finite integer RB counts with positive sizes.");
            end
            stopRB=startRB+sizeRB-1; usableStart=guardRB; usableStop=carrierRB-1-guardRB;
            carrierOK=startRB>=0&&stopRB<carrierRB;
            guardOK=startRB>=usableStart&&stopRB<=usableStop;
            rfStop=rfStartRB+rfSizeRB-1;
            rfOK=startRB>=rfStartRB&&stopRB<=rfStop;
            ssbStop=ssbStartRB+ssbSizeRB-1;
            ssbContained=ssbStartRB>=startRB&&ssbStop<=stopRB;
            reasons=strings(0,1);
            if ~carrierOK,reasons(end+1)="carrier_edge";end %#ok<AGROW>
            if ~guardOK,reasons(end+1)="guard_band";end %#ok<AGROW>
            if ~rfOK,reasons(end+1)="mandatory_rf_span";end %#ok<AGROW>
            if ~ssbContained,reasons(end+1)="ssb_not_contained";end %#ok<AGROW>
            if isempty(reasons),reason="feasible";else,reason=strjoin(reasons,"|");end
            out=struct("StartRB",startRB,"SizeRB",sizeRB,"StopRB",stopRB, ...
                "CarrierContained",carrierOK,"GuardContained",guardOK, ...
                "RFSpanContained",rfOK,"SSBContained",ssbContained, ...
                "Feasible",carrierOK&&guardOK&&rfOK&&ssbContained, ...
                "Reason",reason);
        end
    end
end
