classdef IntegrationInvariantGuard
    %INTEGRATIONINVARIANTGUARD Fail-closed cross-domain acceptance checks.
    methods (Static)
        function requireCommonImplementation(a,b)
            if string(a) ~= string(b)
                error("sixgr:integration:CommonPHYImplementationMismatch", ...
                    "Both run modes must use the same implementation digest.");
            end
        end
        function requireMeasuredSINR(value)
            if ~isscalar(value) || ~isfinite(value)
                error("sixgr:integration:MeasuredSINRRequired", ...
                    "Measured receiver SINR is mandatory.");
            end
        end
        function requirePowerClosure(expected,measured,toleranceDB)
            errorDB = 10*log10(max(double(measured),realmin)/ ...
                max(double(expected),realmin));
            if abs(errorDB) > double(toleranceDB)
                error("sixgr:integration:PowerReconciliationFailure", ...
                    "Power ledger error %.6f dB exceeds %.6f dB.", ...
                    errorDB,double(toleranceDB));
            end
        end
        function requireComplete(state,mandatoryPassed)
            if string(state) ~= "COMPLETED" || ~logical(mandatoryPassed)
                error("sixgr:integration:InvalidCompletionState", ...
                    "Only a completed run with every mandatory gate passed is final.");
            end
        end
        function prohibitConfiguredState(source)
            if startsWith(lower(string(source)),"configured")
                error("sixgr:integration:ConfiguredStateOverride", ...
                    "Connected state must be derived from decoded evidence.");
            end
        end
        function prohibitReceiverOracle(fieldName)
            prohibited = ["ExpectedBits","TransmittedBits","ExpectedUCI", ...
                "TrueChannel","TrueCFO","TrueTiming"];
            if ismember(string(fieldName),prohibited)
                error("sixgr:integration:ReceiverOracleInput", ...
                    "Receiver oracle input %s is prohibited.",fieldName);
            end
        end
        function requireHash(expected,actual,errorID)
            if string(expected) ~= string(actual)
                error(char(string(errorID)),"Digest mismatch.");
            end
        end
        function requireRunClassEvidence(subprofile,gateClass)
            if string(subprofile) == "calibration_grant" && ...
                    string(gateClass) == "connected_network"
                error("sixgr:integration:RunClassEvidenceLeakage", ...
                    "Calibration grants cannot satisfy connected-network gates.");
            end
        end
        function prohibitGlobalRNG(source)
            if string(source) == "global"
                error("sixgr:integration:GlobalRNGProhibited", ...
                    "Production tasks require deterministic named substreams.");
            end
        end
        function requireHARQIdentity(expected,actual)
            if sixgr.integration.IntegrationHash.data(expected) ~= ...
                    sixgr.integration.IntegrationHash.data(actual)
                error("sixgr:integration:HARQIdentityMismatch", ...
                    "HARQ identity does not match the transport block.");
            end
        end
        function requireHARQPosition(expected,actual)
            if ~isequal(expected,actual)
                error("sixgr:integration:HARQPositionMismatch", ...
                    "HARQ rate-match positions do not match.");
            end
        end
        function requireAppliedPrecoder(selected,applied)
            if string(selected) ~= string(applied)
                error("sixgr:integration:PrecoderApplicationMismatch", ...
                    "Selected and applied precoder digests differ.");
            end
        end
        function requireRank(configured,applied)
            if double(configured) ~= double(applied)
                error("sixgr:integration:RankCollapse", ...
                    "Configured rank was not preserved by the applied waveform.");
            end
        end
        function requireExactRunID(requested,actual)
            if string(requested) ~= string(actual)
                error("sixgr:integration:ExactRunIDRequired", ...
                    "Run lookup requires an exact identifier.");
            end
        end
        function requireWaveformInterference(value)
            if isnumeric(value) && isscalar(value)
                error("sixgr:integration:WaveformInterferenceRequired", ...
                    "Geometry interference requires sample-domain contributions.");
            end
        end
        function requireFreshArtifact(expectedRunID,artifactRunID)
            if string(expectedRunID) ~= string(artifactRunID)
                error("sixgr:integration:StaleArtifact", ...
                    "Artifact belongs to a different run.");
            end
        end
        function requireTaskHash(taskID,existingHash,newHash)
            if string(existingHash) ~= string(newHash)
                error("sixgr:integration:TaskConflict", ...
                    "Task %s produced conflicting output hashes.",string(taskID));
            end
        end
        function prohibitRel20Normative(profile,normative)
            if string(profile) == sixgr.integration.RadioProfile.Rel20Study && ...
                    logical(normative)
                error("sixgr:integration:StudyConformanceClaimProhibited", ...
                    "A Release-20 study cannot be marked normative.");
            end
        end
    end
end
