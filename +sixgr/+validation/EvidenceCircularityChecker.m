classdef EvidenceCircularityChecker
    %EVIDENCECIRCULARITYCHECKER Reject shared or DUT-derived evidence roots.
    methods (Static)
        function result=check(expectedProvenance,expectedRoot, ...
                appliedProvenance,appliedRoot)
            expected=localExpected(expectedProvenance);
            applied=sixgr.validation.EvidenceProvenanceClass.parse(appliedProvenance);
            if expected=="DUT_OUTPUT"
                error("sixgr:validation:ReferenceNotIndependent", ...
                    "A DUT output cannot serve as its own reference.");
            end
            if ~sixgr.validation.EvidenceProvenanceClass.qualifiesRuntime(applied)
                if applied=="CONFIGURED" || applied=="RECONSTRUCTED_DIAGNOSTIC"
                    if string(expectedRoot)==string(appliedRoot)
                        error("sixgr:validation:ProvenanceCircular", ...
                            "Expected and applied evidence share a configured root.");
                    end
                    error("sixgr:validation:ObservedEvidenceMissing", ...
                        "Applied evidence is not observed runtime state.");
                end
                error("sixgr:validation:ProvenanceCircular", ...
                    "Applied evidence is derived from a disallowed source.");
            end
            if string(expectedRoot)==string(appliedRoot)
                error("sixgr:validation:ProvenanceCircular", ...
                    "Expected and applied evidence share a disallowed DUT root.");
            end
            result=struct("Allowed",true,"ExpectedRoot",string(expectedRoot), ...
                "AppliedRoot",string(appliedRoot),"Status","PASS");
        end
    end
end

function out=localExpected(value)
try
    out=sixgr.validation.EvidenceProvenanceClass.parse(value);
catch ME
    if ME.identifier~="sixgr:validation:UnknownEvidenceProvenance"
        rethrow(ME);
    end
    out=sixgr.validation.OracleType.parse(value);
end
end
