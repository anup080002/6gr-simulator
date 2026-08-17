classdef Phase7TruthEvaluator
%PHASE7TRUTHEVALUATOR Compose scientific-readiness Phase 7 evidence gates.
%   Phase7Ok and ResultOk are deliberately fail-closed. Callers must pass
%   explicit true flags for every required gate; missing flags evaluate false.

    methods (Static)
        function status = evaluate(flags)
            if nargin < 1 || ~isstruct(flags)
                flags = struct();
            end

            gateNames = sixgr.runtime.Phase7TruthEvaluator.gateNames();
            notApplicable = string(sixgr.util.structGet(flags, ...
                "NotApplicableGateNames", strings(0, 1)));
            notApplicable = unique(strtrim(notApplicable(:)), "stable");
            notApplicable = notApplicable(strlength(notApplicable) > 0);
            unknownNotApplicable = setdiff(notApplicable, gateNames, "stable");
            if ~isempty(unknownNotApplicable)
                error("sixgr:runtime:UnknownPhase7GateApplicability", ...
                    "Unknown Phase-7 not-applicable gate(s): %s", ...
                    char(strjoin(unknownNotApplicable, ", ")));
            end
            status = struct();
            failureCodes = strings(0, 1);
            phase7Ok = true;
            for i = 1:numel(gateNames)
                name = gateNames(i);
                value = logical(sixgr.util.structGet(flags, char(name), false));
                status.(char(name)) = value;
                applicable = ~ismember(name, notApplicable);
                phase7Ok = phase7Ok && (~applicable || value);
                if applicable && ~value
                    failureCodes(end+1, 1) = name + "_false"; %#ok<AGROW>
                end
            end

            phaseOk = true;
            for name = ["Phase1Ok","Phase2Ok","Phase3Ok","Phase4Ok","Phase5Ok","Phase6Ok"]
                value = logical(sixgr.util.structGet(flags, char(name), false));
                status.(char(name)) = value;
                phaseOk = phaseOk && value;
                if ~value
                    failureCodes(end+1, 1) = name + "_false"; %#ok<AGROW>
                end
            end

            status.Phase7Ok = logical(phase7Ok);
            status.ResultOk = logical(phaseOk && phase7Ok);
            status.PublicationReadinessOk = logical(sixgr.util.structGet(flags, ...
                "PublicationReadinessOk", false) && phase7Ok);
            if ~status.PublicationReadinessOk
                failureCodes(end+1, 1) = "PublicationReadinessOk_false"; %#ok<AGROW>
            end
            status.ResultOkAuthority = "all_phase_gates_required_no_lower_pass_override";
            status.NotApplicableGateNames = notApplicable;
            status.ApplicabilityAuthority = "operator_run_class_and_concrete_channel_model";
            status.ScopeLabel = "SCOPED_IMPLEMENTATION_VALIDATION";
            status.FailureCodes = failureCodes;
            status.PrimaryFailureCode = localPrimaryFailure(failureCodes);
            status.GeneratedAt = sixgr.util.utcNowISO8601();
            status.ProducerModule = "sixgr.runtime.Phase7TruthEvaluator";
        end

        function names = gateNames()
            names = [
                "ResolvedConfigurationConsistentOk"
                "CapturePolicyTruthfulOk"
                "GeometryValidationOk"
                "FullTrajectoryExecutedOk"
                "MobilityStateContinuousOk"
                "InterUeConstraintResolvedOk"
                "LosStateModelOk"
                "PathlossReconciliationOk"
                "ShadowFadingReconciliationOk"
                "LargeScaleParameterReconciliationOk"
                "CdlRealizationOk"
                "ChannelStateContinuityOk"
                "PathPowerNormalizationOk"
                "DopplerReconciliationOk"
                "PropagationDelayReconciliationOk"
                "AntennaArrayReconciliationOk"
                "PolarizationReconciliationOk"
                "NoiseReconciliationOk"
                "InterferenceAccountingOk"
                "RfChainDefinitionOk"
                "CfoConfiguredAppliedOk"
                "PhaseNoiseConfiguredAppliedOk"
                "TimingOffsetConfiguredAppliedOk"
                "IqImbalanceConfiguredAppliedOk"
                "PaConfiguredAppliedOk"
                "EvmReconciliationOk"
                "PaprReconciliationOk"
                "ChannelRfConfiguredVsAppliedOk"
                "CheckpointResumeEquivalenceOk"
                "SeedHierarchyOk"
                "CampaignDesignOk"
                "CampaignCompletionOk"
                "MultiSeedDropStatisticsOk"
                "CanonicalKpiLedgerOk"
                "ThroughputReconciliationOk"
                "BlerBerReconciliationOk"
                "LatencyReconciliationOk"
                "AccessKpiReconciliationOk"
                "SchedulerKpiReconciliationOk"
                "MobilityKpiReconciliationOk"
                "MimoKpiReconciliationOk"
                "EnergyModelOk"
                "ConfidenceIntervalsOk"
                "SampleAdequacyOk"
                "SweepDataQualityOk"
                "SerialParallelDeterminismOk"
                "PerformanceProfileOk"
                "LongRunStabilityOk"
                "OutputSchemaValidationOk"
                "ArtifactCompletenessOk"
                "PlotDataLineageOk"
                "Phase7NoFabricationOk"
                "Phase7ProvenanceOk"
                "TwoModeAcceptanceGatesOk"
                "FinalScientificClaimsTruthfulOk"];
        end

        function T = table(status)
            % A status has scalar gate fields but FailureCodes is a
            % variable-length diagnostic vector.  Writing that vector
            % directly through struct2table expands a nominally one-row
            % record and produces a non-rectangular CSV.  Keep the JSON
            % representation lossless and serialize only the tabular view.
            tabular = status;
            failureCodes = string(sixgr.util.structGet(tabular, ...
                "FailureCodes", strings(0, 1)));
            failureCodes = strtrim(failureCodes(:));
            failureCodes = failureCodes(strlength(failureCodes) > 0);
            tabular.FailureCodes = string(strjoin(failureCodes, ";"));
            notApplicable = string(sixgr.util.structGet(tabular, ...
                "NotApplicableGateNames", strings(0, 1)));
            notApplicable = strtrim(notApplicable(:));
            notApplicable = notApplicable(strlength(notApplicable) > 0);
            tabular.NotApplicableGateNames = string(strjoin(notApplicable, ";"));
            T = struct2table(tabular, "AsArray", true);
        end
    end
end

function code = localPrimaryFailure(failureCodes)
if isempty(failureCodes)
    code = "";
else
    code = string(failureCodes(1));
end
end
