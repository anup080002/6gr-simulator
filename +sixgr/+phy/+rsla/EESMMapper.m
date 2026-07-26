classdef EESMMapper
    %EESMMAPPER Linear-domain EESM with explicit calibrated beta.

    methods (Static)
        function result = map(sinrPerREDb,betaDb,datasetID)
            if nargin<3 || strlength(string(datasetID))==0 || ...
                    ~(isscalar(betaDb)&&isfinite(betaDb))
                error("RSLA:MissingEffectiveSINRCalibration", ...
                    "EESM requires an exact profile-keyed dataset and beta.");
            end
            sinrPerREDb = double(sinrPerREDb(:));
            if isempty(sinrPerREDb) || any(~isfinite(sinrPerREDb))
                error("RSLA:MissingMeasuredInput", ...
                    "EESM requires finite receiver-derived per-RE SINR.");
            end
            gamma = 10.^(sinrPerREDb/10);
            beta = 10.^(double(betaDb)/10);
            effectiveLinear = -beta*log(mean(exp(-gamma/beta)));
            result = struct("Method","EESM", ...
                "EffectiveSINRLinear",effectiveLinear, ...
                "EffectiveSINRDb",10*log10(effectiveLinear), ...
                "ParameterValue",betaDb,"DatasetID",string(datasetID), ...
                "InputSHA256",sixgr.phy.rsla.RSLAUtil.hash(sinrPerREDb));
        end
    end
end
