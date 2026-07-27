classdef RuntimeEvidenceGate
    %RUNTIMEEVIDENCEGATE Strict authority check for runtime fields.
    methods (Static)
        function result=validate(provenance,sampleCount)
            if ~sixgr.validation.EvidenceProvenanceClass.qualifiesRuntime(provenance)
                error("sixgr:validation:ObservedEvidenceMissing", ...
                    "Mandatory runtime evidence is not observed or receiver-derived.");
            end
            if ~(isnumeric(sampleCount)&&isscalar(sampleCount)&& ...
                    isfinite(sampleCount)&&sampleCount>=1&&sampleCount==fix(sampleCount))
                error("sixgr:validation:ObservedEvidenceMissing", ...
                    "Mandatory runtime evidence requires at least one sample.");
            end
            result=struct("Qualified",true,"SampleCount",double(sampleCount), ...
                "Status","PASS");
        end
    end
end
