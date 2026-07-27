classdef IntegrationPlanningResult
    %INTEGRATIONPLANNINGRESULT Immutable resolved execution claim.
    properties (SetAccess=immutable)
        RunMode (1,1) string
        RadioProfile (1,1) string
        Subprofile (1,1) string
        RunClass (1,1) string
        EnvironmentAdapter (1,1) string
        Normative (1,1) logical
        ResearchClass (1,1) string
        TraceProfile (1,1) string
    end
    methods
        function obj = IntegrationPlanningResult(mode,profile,subprofile, ...
                runClass,adapter,normative,researchClass,traceProfile)
            obj.RunMode = string(mode);
            obj.RadioProfile = string(profile);
            obj.Subprofile = string(subprofile);
            obj.RunClass = string(runClass);
            obj.EnvironmentAdapter = string(adapter);
            obj.Normative = logical(normative);
            obj.ResearchClass = string(researchClass);
            obj.TraceProfile = string(traceProfile);
        end
        function value = toStruct(obj)
            value = struct("RunMode",obj.RunMode, ...
                "RadioProfile",obj.RadioProfile,"Subprofile",obj.Subprofile, ...
                "RunClass",obj.RunClass,"EnvironmentAdapter", ...
                obj.EnvironmentAdapter,"Normative",obj.Normative, ...
                "ResearchClass",obj.ResearchClass, ...
                "TraceProfile",obj.TraceProfile);
        end
    end
end
