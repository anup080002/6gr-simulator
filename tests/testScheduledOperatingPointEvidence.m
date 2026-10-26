function ok = testScheduledOperatingPointEvidence()
%TESTSCHEDULEDOPERATINGPOINTEVIDENCE Guard grant-bound row provenance.

T = table(true, true, 7, "16QAM", "scheduler_grant", ...
    "dir=DL;frame=0;slot=2;ue=1", ...
    'VariableNames', {'AdaptiveMode','LinkAdaptationScheduled','MCSIndex', ...
    'Modulation','GrantOperatingPointSource','GrantContextId'});
actual = sixgr.link.applyScheduledOperatingPointEvidence(T);
assert(actual.ScheduledMCS == 7 && actual.ScheduledMCSIndex == 7);
assert(actual.ScheduledModulation == "16QAM");
assert(actual.ScheduledOperatingPointSource == "scheduler_grant");
assert(actual.ScheduledOperatingPointEvidenceStatus == ...
    "materialized_from_executed_frozen_scheduler_grant");
assert(actual.ScheduledOperatingPointMatchesTransmitted);

missing = T;
missing.GrantContextId = "";
missing = sixgr.link.applyScheduledOperatingPointEvidence(missing);
assert(isnan(missing.ScheduledMCS));
assert(missing.ScheduledOperatingPointEvidenceStatus == ...
    "missing_frozen_scheduler_grant_operating_point_evidence");
assert(~missing.ScheduledOperatingPointMatchesTransmitted);

fixed = T;
fixed.AdaptiveMode = false;
fixed.LinkAdaptationScheduled = false;
fixed = sixgr.link.applyScheduledOperatingPointEvidence(fixed);
assert(isnan(fixed.ScheduledMCS));
assert(fixed.ScheduledOperatingPointEvidenceStatus == ...
    "not_applicable_no_adaptive_scheduled_decision");

conflict = T;
conflict.ScheduledMCS = 8;
conflict.ScheduledMCSIndex = 8;
conflict.ScheduledModulation = "64QAM";
conflict = sixgr.link.applyScheduledOperatingPointEvidence(conflict);
assert(conflict.ScheduledOperatingPointEvidenceStatus == ...
    "frozen_scheduler_grant_operating_point_conflict");
assert(~conflict.ScheduledOperatingPointMatchesTransmitted);

% A coupled execution may retain the upstream CQI selection policy in
% GrantOperatingPointSource.  The immutable frozen-grant identifier is the
% authority that proves the scheduled values were actually transmitted.
selectedByCQI = T;
selectedByCQI.GrantOperatingPointSource = "cqi_link_adaptation";
selectedByCQI.FrozenGrantContextId = "sha256:frozen-grant";
selectedByCQI = sixgr.link.applyScheduledOperatingPointEvidence(selectedByCQI);
assert(selectedByCQI.ScheduledMCS == selectedByCQI.MCSIndex);
assert(selectedByCQI.ScheduledModulation == selectedByCQI.Modulation);
assert(selectedByCQI.ScheduledOperatingPointSource == ...
    "scheduler_grant_from_cqi_link_adaptation");
assert(selectedByCQI.ScheduledOperatingPointEvidenceStatus == ...
    "materialized_from_executed_frozen_scheduler_grant");
assert(selectedByCQI.ScheduledOperatingPointMatchesTransmitted);

% A received report was consumed by this grant; the receiver need not emit
% another future update. The original false flag must remain unchanged.
consumed=selectedByCQI;
consumed.LinkAdaptationScheduled=false;
consumed.PDCCHGrantBindingOk=true;
consumed.ScheduledMCS=NaN; consumed.ScheduledMCSIndex=NaN;
consumed.ScheduledModulation="";
consumed.ScheduledOperatingPointEvidenceStatus="not_applicable_no_adaptive_scheduled_decision";
consumed=sixgr.link.applyScheduledOperatingPointEvidence(consumed);
assert(consumed.ScheduledMCS==consumed.MCSIndex && ...
    consumed.ScheduledOperatingPointMatchesTransmitted && ~consumed.LinkAdaptationScheduled);
assert(consumed.ScheduledOperatingPointEvidenceStatus=="materialized_from_executed_frozen_scheduler_grant");
assert(isequaln(consumed,sixgr.link.applyScheduledOperatingPointEvidence(consumed)));
% A false future-update flag cannot substitute for missing current authority.
unbound=T; unbound.LinkAdaptationScheduled=false;
unbound.GrantOperatingPointSource="receiver_cqi_only";
unbound=sixgr.link.applyScheduledOperatingPointEvidence(unbound);
assert(isnan(unbound.ScheduledMCS) && ~unbound.ScheduledOperatingPointMatchesTransmitted && ...
    unbound.ScheduledOperatingPointEvidenceStatus=="missing_frozen_scheduler_grant_operating_point_evidence");
% Received DCI binding plus current context is an independent supported path.
decoded=T; decoded.LinkAdaptationScheduled=false;
decoded.GrantOperatingPointSource="cqi_link_adaptation"; decoded.PDCCHGrantBindingOk=true;
decoded=sixgr.link.applyScheduledOperatingPointEvidence(decoded);
assert(decoded.ScheduledMCS==7 && decoded.ScheduledOperatingPointMatchesTransmitted);

empty = sixgr.link.applyScheduledOperatingPointEvidence(table());
required = ["ScheduledMCS","ScheduledMCSIndex","ScheduledModulation", ...
    "ScheduledOperatingPointSource", ...
    "ScheduledOperatingPointEvidenceStatus", ...
    "ScheduledOperatingPointMatchesTransmitted"];
assert(all(ismember(required, string(empty.Properties.VariableNames))));
assert(height(empty) == 0);
ok = true;
end
