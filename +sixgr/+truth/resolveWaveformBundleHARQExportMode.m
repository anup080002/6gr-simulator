function mode = resolveWaveformBundleHARQExportMode(isCoupledTruth, runtimeTimelineReady, ...
    diagnosticsEnabled, summaryReady, previewOnly, legacyArtifactsReady)
%RESOLVEWAVEFORMBUNDLEHARQEXPORTMODE Select a scope-safe HARQ export path.
%
% A slot-coupled truth run may publish only observations produced by its
% canonical runtime.  A separate waveform campaign has a different run
% scope and therefore cannot be substituted when the canonical timeline is
% empty.

arguments
    isCoupledTruth (1,1) logical
    runtimeTimelineReady (1,1) logical
    diagnosticsEnabled (1,1) logical
    summaryReady (1,1) logical
    previewOnly (1,1) logical
    legacyArtifactsReady (1,1) logical
end

if runtimeTimelineReady
    mode = "runtime_observation_reuse";
elseif isCoupledTruth
    mode = "unavailable_no_canonical_observation";
elseif ~diagnosticsEnabled
    mode = "disabled_no_runtime_observation";
elseif ~summaryReady || previewOnly || ~legacyArtifactsReady
    mode = "standalone_export";
else
    mode = "reuse";
end
end
