classdef WaveformPlanningResult
    %WAVEFORMPLANNINGRESULT Immutable pre-sample capability decision.

    properties (SetAccess=immutable)
        ProfileID (1,1) string
        Feature (1,1) string
        Outcome (1,1) string
        ErrorID (1,1) string
        NormativeClaimAllowed (1,1) logical
        EvidenceClass (1,1) string
    end

    methods
        function obj = WaveformPlanningResult(profile,feature,outcome,errorID,normative,evidence)
            obj.ProfileID = string(profile);
            obj.Feature = string(feature);
            obj.Outcome = string(outcome);
            obj.ErrorID = string(errorID);
            obj.NormativeClaimAllowed = logical(normative);
            obj.EvidenceClass = string(evidence);
        end

        function requireExecutable(obj)
            if obj.Outcome ~= "EXECUTE"
                error(char(obj.ErrorID), ...
                    "Waveform profile '%s' rejects feature '%s'.", ...
                    obj.ProfileID,obj.Feature);
            end
        end

        function value = toStruct(obj)
            value = struct("ProfileID",obj.ProfileID,"Feature",obj.Feature, ...
                "Outcome",obj.Outcome,"ErrorID",obj.ErrorID, ...
                "NormativeClaimAllowed",obj.NormativeClaimAllowed, ...
                "EvidenceClass",obj.EvidenceClass);
        end
    end
end
