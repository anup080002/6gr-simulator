classdef MIESMMapper
    %MIESMMAPPER Calibrated bounded MI transform/inverse mapping.

    methods (Static)
        function result = map(sinrPerREDb,scaleLinear,datasetID)
            if nargin<3 || strlength(string(datasetID))==0 || ...
                    ~(isscalar(scaleLinear)&&isfinite(scaleLinear)&&scaleLinear>0)
                error("RSLA:MissingEffectiveSINRCalibration", ...
                    "MIESM requires an exact profile-keyed calibrated mapping.");
            end
            values = double(sinrPerREDb(:));
            if isempty(values) || any(~isfinite(values))
                error("RSLA:MissingMeasuredInput", ...
                    "MIESM requires finite receiver-derived per-RE SINR.");
            end
            gamma = 10.^(values/10);
            information = 1-exp(-gamma/double(scaleLinear));
            meanInformation = min(max(mean(information),0),1-eps);
            effectiveLinear = -double(scaleLinear)*log(1-meanInformation);
            result = struct("Method","MIESM", ...
                "EffectiveSINRLinear",effectiveLinear, ...
                "EffectiveSINRDb",10*log10(effectiveLinear), ...
                "ParameterValue",scaleLinear,"DatasetID",string(datasetID), ...
                "MeanMutualInformation",meanInformation, ...
                "InputSHA256",sixgr.phy.rsla.RSLAUtil.hash(values));
        end
    end
end
