function report = verifyFunctionRegistry(varargin)
%VERIFYFUNCTIONREGISTRY Verify Prompt 9 capabilities against repo functions.
%
% The registry is capability-based: Prompt 9 names are resolved to accepted
% existing implementation paths where this repository already uses different
% concrete function names.

p = inputParser;
p.addParameter("Strict", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("WritePath", "", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

repoRoot = sixgr.utils.getRepoRoot();
specs = localCapabilitySpecs();
rows = repmat(struct("PromptBlock", "", "Capability", "", "Required", true, ...
    "Exists", false, "Status", "", "ResolvedPath", "", "CandidatePaths", ""), numel(specs), 1);
for i = 1:numel(specs)
    spec = specs(i);
    [existsFlag, resolved] = localResolveAny(repoRoot, spec.Candidates);
    rows(i) = struct("PromptBlock", spec.Block, "Capability", spec.Capability, ...
        "Required", spec.Required, "Exists", existsFlag, ...
        "Status", localStatus(existsFlag, spec.Required), ...
        "ResolvedPath", resolved, "CandidatePaths", strjoin(string(spec.Candidates), "|"));
end
T = struct2table(rows, "AsArray", true);
missing = T.Required & ~T.Exists;

report = struct();
report.Ok = ~any(missing);
report.Table = T;
report.Missing = string(T.Capability(missing));
report.RepositoryRoot = string(repoRoot);

writePath = string(opt.WritePath);
if strlength(strtrim(writePath)) > 0
    sixgr.analytics.writeAnalysisTable(writePath, T);
end

if logical(opt.Strict) && ~report.Ok
    error("sixgr:utils:verifyFunctionRegistry:MissingFunctions", ...
        "%d required Prompt 9 capability function(s) are missing: %s", ...
        sum(missing), strjoin(report.Missing, ", "));
end
end

function specs = localCapabilitySpecs()
items = {
    "Prompt1", "export_timeout_guard", true, ["+sixgr/+utils/exportWithTimeout.m"]
    "Prompt1", "link_adaptation_update", true, ["+sixgr/+link/updateLinkAdaptationState.m","+sixgr/+link/applyLinkAdaptationDecision.m"]
    "Prompt2", "sib1_waveform_decode", true, ["+sixgr/+phy/+broadcast/recoverSIB1FromWaveform.m","+sixgr/+link/runCellSearch_MIB_SIB1.m"]
    "Prompt2", "coreset0_from_mib", true, ["+sixgr/+phy/+broadcast/deriveType0PDCCHFromMIB.m"]
    "Prompt2", "strict_sib1_validation", true, ["+sixgr/+phy/+broadcast/runSIB1StrictMiniAnchor.m"]
    "Prompt2", "prach_waveform_generation", true, ["+sixgr/+phy/+prach/generatePRACHWaveform.m","+sixgr/+rach/generatePRACHWaveform.m"]
    "Prompt2", "prach_waveform_detection", true, ["+sixgr/+phy/+prach/detectPRACHWaveform.m","+sixgr/+rach/PRACHDetector.m"]
    "Prompt2", "strict_prach_validation", true, ["+sixgr/+phy/+prach/runStrictPRACHValidation.m"]
    "Prompt2", "four_step_ra", true, ["+sixgr/+phy/+ra/runFourStepRA.m"]
    "Prompt2", "rar_payload_decode", true, ["+sixgr/+mac/+ra/decodeMACRAR.m","+sixgr/+phy/+ra/recoverMsg2RAR.m"]
    "Prompt3", "dci_payload_encode_decode", true, ["+sixgr/+phy/+pdcch/encodeDCIPayload.m","+sixgr/+phy/+pdcch/decodeDCIPayload.m"]
    "Prompt3", "dci_10_assignment", true, ["+sixgr/+phy/+pdcch/buildDCI10DownlinkAssignment.m"]
    "Prompt3", "dci_00_grant", true, ["+sixgr/+phy/+pdcch/buildDCI00UplinkGrant.m"]
    "Prompt3", "pdcch_tx_rx", true, ["+sixgr/+phy/+dl/PDCCH_Tx.m","+sixgr/+phy/+dl/PDCCH_Rx.m"]
    "Prompt3", "strict_pdcch_validation", true, ["+sixgr/+phy/+pdcch/runStrictPDCCHValidation.m"]
    "Prompt4", "trs_tracking_receiver", true, ["+sixgr/+link/runTRSTracking.m","+sixgr/+phy/+trs/estimateTRSFrequencyOffset.m"]
    "Prompt4", "strict_trs_validation", true, ["+sixgr/+phy/+trs/runStrictTRSValidation.m"]
    "Prompt4", "srs_receiver", true, ["+sixgr/+phy/+ul/SRS_Rx.m","+sixgr/+phy/+srs/estimateULChannelFromSRS.m"]
    "Prompt4", "strict_srs_validation", true, ["+sixgr/+phy/+srs/runStrictSRSValidation.m"]
    "Prompt4", "channel_rf_evidence", true, ["+sixgr/+channel/runStrictChannelRFValidation.m","+sixgr/+channel/exportStrictChannelRFArtifacts.m"]
    "Prompt5", "nominal_vs_effective_mimo", true, ["+sixgr/+mimo/resolveNominalVsEffectiveMIMO.m"]
    "Prompt5", "pmi_selection", true, ["+sixgr/+mimo/selectPMI.m"]
    "Prompt5", "nr_codebook", true, ["+sixgr/+mimo/buildNRCodebook.m"]
    "Prompt5", "csi_feedback", true, ["+sixgr/+mimo/buildCSIFeedback.m"]
    "Prompt5", "ul_beam_from_srs", true, ["+sixgr/+mimo/selectULBeamFromSRS.m"]
    "Prompt6", "harq_state_manager", true, ["+sixgr/+l2/+mac/HARQEntity.m","+sixgr/+phy/+harq/combineSoftLLR.m"]
    "Prompt6", "pf_scheduler", true, ["+sixgr/+l2/+mac/SchedulerPF.m"]
    "Prompt6", "tdd_slot_partition", true, ["+sixgr/+util/resolveTDDSlotPartition.m"]
    "Prompt7", "pucch_receiver", true, ["+sixgr/+phy/+ul/PUCCH_Rx.m","+sixgr/+phy/+pucch/runStrictPUCCHValidation.m"]
    "Prompt7", "pucch_evidence_writer", true, ["+sixgr/+phy/+pucch/exportStrictPUCCHArtifacts.m"]
    "Prompt7", "parameter_binding_matrix", true, ["+sixgr/+config/buildParameterBindingMatrix.m"]
    "Prompt8", "harq_combining_evidence", true, ["+sixgr/+analytics/measureHARQCombiningGain.m","+sixgr/+truth/exportLLSHARQDiagnostics.m"]
    "Prompt8", "snr_sweep_orchestrator", true, ["+sixgr/+lls6g/+runners/runSingle.m","+sixgr/+truth/runWaveformLinkBundle.m"]
    "Prompt8", "mobility_adequacy", true, ["+sixgr/+analytics/buildMobilityAdequacyReport.m"]
    "Prompt8", "provenance_manifest", true, ["+sixgr/+truth/buildProvenanceManifest.m"]
    "Prompt8", "runtime_call_graph", true, ["+sixgr/+analytics/buildRuntimeCallGraph.m"]
    "CorePHY", "pdsch_tx_rx", true, ["+sixgr/+phy/+dl/PDSCH_Tx.m","+sixgr/+phy/+dl/PDSCH_Rx.m"]
    "CorePHY", "pusch_tx_rx", true, ["+sixgr/+phy/+ul/PUSCH_Tx.m","+sixgr/+phy/+ul/PUSCH_Rx.m"]
    "CorePHY", "pbch_recovery", true, ["+sixgr/+phy/+dl/PBCH_Recovery.m"]
    "Prompt9", "measurement_only_audit", true, ["+sixgr/+audit/verifyMeasurementOnly.m"]
    "Prompt9", "all_evidence_export", true, ["+sixgr/+export/exportAllEvidence.m"]
    };
specs = repmat(struct("Block", "", "Capability", "", "Required", true, "Candidates", strings(0,1)), size(items, 1), 1);
for i = 1:size(items, 1)
    specs(i) = struct("Block", string(items{i, 1}), "Capability", string(items{i, 2}), ...
        "Required", logical(items{i, 3}), "Candidates", string(items{i, 4}));
end
end

function [tf, resolved] = localResolveAny(repoRoot, candidates)
tf = false;
resolved = "";
for candidate = string(candidates)
    p = fullfile(repoRoot, strrep(char(candidate), "/", filesep));
    if exist(p, "file") == 2
        tf = true;
        resolved = candidate;
        return;
    end
end
end

function status = localStatus(existsFlag, required)
if existsFlag
    status = "present";
elseif required
    status = "missing_required";
else
    status = "missing_optional";
end
end
