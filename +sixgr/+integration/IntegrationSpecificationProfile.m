classdef IntegrationSpecificationProfile
    %INTEGRATIONSPECIFICATIONPROFILE Claim boundary for Phase 16.
    properties (Constant)
        ContractVersion = "1.0.0"
    end
    methods (Static)
        function result = resolve(mode,profile,subprofile,traceProfile)
            result = sixgr.integration.IntegrationCapabilityProfile.plan( ...
                mode,profile,subprofile,traceProfile);
            if result.RadioProfile == sixgr.integration.RadioProfile.Rel20Study && ...
                    result.Normative
                error("sixgr:integration:StudyConformanceClaimProhibited", ...
                    "Release-20 study profiles cannot carry a normative claim.");
            end
        end
    end
end
