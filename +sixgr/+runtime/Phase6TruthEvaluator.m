classdef Phase6TruthEvaluator
%PHASE6TRUTHEVALUATOR Compose advanced-PHY Phase 6 evidence gates.
%   Phase6Ok is a phase-specific gate only. It is not a replacement for the
%   full scenario ResultOk, because later channel/RF, duration, and KPI gates
%   remain outside this phase.

    methods (Static)
        function status = evaluate(flags)
            if nargin < 1 || ~isstruct(flags)
                flags = struct();
            end

            gateNames = sixgr.runtime.Phase6TruthEvaluator.gateNames();
            status = struct();
            failureCodes = strings(0, 1);
            phase6Ok = true;

            for i = 1:numel(gateNames)
                name = gateNames(i);
                value = logical(sixgr.util.structGet(flags, char(name), false));
                status.(char(name)) = value;
                phase6Ok = phase6Ok && value;
                if ~value
                    failureCodes(end+1, 1) = name + "_false"; %#ok<AGROW>
                end
            end

            status.Phase6Ok = logical(phase6Ok);
            status.FullScenarioResultOk = logical(sixgr.util.structGet(flags, "FullScenarioResultOk", false));
            status.ResultOkAuthority = "Phase6Ok_is_not_full_scenario_ResultOk";
            status.FailureCodes = failureCodes;
            status.PrimaryFailureCode = localPrimaryFailure(failureCodes);
            status.GeneratedAt = sixgr.util.utcNowISO8601();
            status.ProducerModule = "sixgr.runtime.Phase6TruthEvaluator";
        end

        function names = gateNames()
            names = [ ...
                "Phase5Ok"
                "Phase6RrcConfigurationOk"
                "CsiRsResourceResolutionOk"
                "CsiRsSequenceOk"
                "CsiRsPortMappingOk"
                "CsiRsBeamSweepOk"
                "CsiRsChannelRfApplicationOk"
                "CsiRsChannelEstimationOk"
                "CsiRsMeasurementOk"
                "CriSelectionOk"
                "Type1CodebookOk"
                "RiSelectionOk"
                "PmiSelectionOk"
                "CqiCalculationOk"
                "CsiReportConstructionOk"
                "CsiPart1Ok"
                "CsiPart2Ok"
                "CsiReportTimingOk"
                "PucchFormat2EncodingOk"
                "PucchFormat2DecodeOk"
                "CsiReportOverAirOk"
                "GnbCsiStateOk"
                "CsiAgeValidityOk"
                "SrsConfigurationOk"
                "SrsSequenceOk"
                "SrsPowerControlOk"
                "SrsChannelRfApplicationOk"
                "SrsChannelEstimationOk"
                "ReciprocityModelOk"
                "ReciprocityCalibrationOk"
                "ChannelAgeModelOk"
                "ChannelPredictionOk"
                "TrsConfigurationOk"
                "TrsTrackingOk"
                "PdschPtrsOk"
                "PuschPtrsOk"
                "DlRankAdaptationOk"
                "UlRankAdaptationOk"
                "Rank2PdschOk"
                "Rank2PuschOk"
                "PrecoderPowerNormalizationOk"
                "DlMuMimoPairingOk"
                "DlMuMimoPrecodingOk"
                "DlMuMimoTransmissionOk"
                "DlMuMimoDecodeOk"
                "UlMuMimoPairingOk"
                "UlMuMimoTransmissionOk"
                "UlMuMimoJointReceiverOk"
                "MimoSchedulerIntegrationOk"
                "RankAwareLinkAdaptationOk"
                "Phase6NoOracleOk"
                "Phase6DecodedConfigOwnershipOk"
                "Phase6MathematicalReconciliationOk"
                "Phase6ArtifactValidationOk"];
        end

        function T = table(status)
            T = struct2table(status, "AsArray", true);
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
