function [obligation,report,calendar,evidence]=resolveSharedPUSCHCSIReceiveObligation(state,cfg,grant)
% Installed calendar/schema plus actual gNB reference-TX applicability.
% Keep the pure configuration builder separate for planning/validation.
[obligation,report,calendar]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,grant);
evidence=table();
if isempty(report), return; end
[eligible,evidence]=sixgr.truth.resolveCSIReceiveReferenceEvidence( ...
    state,cfg,grant.UEIndex,grant.ServingCell,calendar, ...
    double(grant.TimingDecision.DataAbsoluteSlot)+1);
assert(isscalar(eligible),'sixgr:truth:AmbiguousScheduledPUSCHCSI', ...
    'Resolve one independently configured CSI obligation for this PUSCH.');
if ~eligible
    obligation=struct('ReportConfigID',"",'ConfigurationEpoch',NaN);
    report=[];
end
end
