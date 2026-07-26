classdef StrictMIMOValidator
    %STRICTMIMOVALIDATOR Shared fail-before-waveform invariant checks.

    methods (Static)
        function validateSubsetRestriction(bits, expectedLength)
            bits = double(bits(:));
            if numel(bits) ~= expectedLength || any(~ismember(bits,[0 1]))
                error("sixgr:mimo:InvalidCodebookSubsetRestriction", ...
                    "Codebook subset restriction must contain %d binary values.", ...
                    expectedLength);
            end
        end

        function assertNoConfiguredOverride(configuredValue, authoritativeValue)
            if ~isempty(configuredValue) && ~isequaln(configuredValue,authoritativeValue)
                error("sixgr:mimo:ConfiguredPrecoderOverride", ...
                    "Configuration cannot override an authoritative measured precoder decision.");
            end
        end

        function validateApplication(selectedW,appliedW,scheduledRank,appliedRank, ...
                configuredPorts,appliedPorts)
            if scheduledRank ~= appliedRank
                error("sixgr:mimo:RankCollapse", ...
                    "Applied rank %d differs from scheduled rank %d.", ...
                    appliedRank,scheduledRank);
            end
            if ~isequal(double(configuredPorts(:)),double(appliedPorts(:)))
                error("sixgr:mimo:PortCollapse", ...
                    "Applied logical/physical ports differ from the assignment.");
            end
            sixgr.phy.mimo.MatrixContract.assertApplied(selectedW,appliedW);
        end

        function validateSRSDecision(state,currentSlot)
            if isempty(state) || ~isstruct(state) || ...
                    ~isfield(state,"Measured") || ~logical(state.Measured)
                error("sixgr:mimo:MissingSRSDecision", ...
                    "UL codebook PUSCH requires measured SRS decision state.");
            end
            slot = double(localRequired(state,"Slot","sixgr:mimo:MissingSRSDecision"));
            maxAge = double(localRequired(state,"MaxAgeSlots","sixgr:mimo:MissingSRSDecision"));
            if currentSlot-slot > maxAge
                error("sixgr:mimo:StaleSRSDecision", ...
                    "Measured SRS decision is stale.");
            end
        end

        function validateTCI(activeState,scheduledState)
            if isempty(activeState) || ~isfinite(double(activeState))
                error("sixgr:mimo:InactiveTCIState", ...
                    "Scheduled TCI state is not active.");
            end
            if double(activeState) ~= double(scheduledState)
                error("sixgr:mimo:QCLSourceMismatch", ...
                    "Active QCL/TCI source differs from the scheduled state.");
            end
        end

        function validateBeamMeasurement(provenance,resourceID)
            if contains(lower(string(provenance)),["geometry","configured_winner","oracle"])
                error("sixgr:mimo:BeamMeasurementOracleForbidden", ...
                    "Strict beam selection must come from measured reference signals.");
            end
            if strlength(string(resourceID)) == 0
                error("sixgr:mimo:BeamReportMismatch", ...
                    "Beam report requires measured resource identity.");
            end
        end
    end
end

function value = localRequired(s,name,errorID)
if ~isfield(s,name) || isempty(s.(name))
    error(errorID,"State requires field %s.",name);
end
value = s.(name);
end
