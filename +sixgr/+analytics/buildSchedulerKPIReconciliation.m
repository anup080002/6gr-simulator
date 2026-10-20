function T = buildSchedulerKPIReconciliation(dl, ul, cfg)
%BUILDSCHEDULERKPIRECONCILIATION One owner for receiver-backed scheduler KPIs.
% This is an audit, not elapsed-run throughput or application delivery. Its
% denominator sums trial exposure, including retransmissions and simultaneous
% UE trials. Never replace that ratio by an unweighted mean of row rates.
if nargin < 3, cfg = struct(); end
[dl, dlBits] = localReceiverPopulation(dl);
[ul, ulBits] = localReceiverPopulation(ul);
[dlRate, dlBits, dlTime, dlBasis] = localRate(dl, dlBits, cfg);
[ulRate, ulBits, ulTime, ulBasis] = localRate(ul, ulBits, cfg);
[dlBLER, dlObserved, dlUnknown] = localBLER(dl);
[ulBLER, ulObserved, ulUnknown] = localBLER(ul);
applicable = ~logical(sixgr.util.structGet(cfg, 'run.fixedLinkCampaignOnly', ...
    sixgr.util.structGet(cfg, 'canonical_control.run.fixed_link_campaign_only', ...
    sixgr.util.structGet(cfg, 'sweeps_and_matrix.fixed_link_calibration.only', false))));
ok = applicable && height(dl)>0 && height(ul)>0 && dlUnknown==0 && ulUnknown==0 && ...
    isfinite(dlRate) && dlRate>0 && isfinite(ulRate) && ulRate>0;
T = table(height(dl), height(ul), dlBits, ulBits, dlTime, ulTime, dlRate, ulRate, ...
    dlBLER, ulBLER, ok, "receiver_crc_logical_TB_credit_and_trial_exposure", ...
    'VariableNames', {'DL_GrantCount','UL_GrantCount','DL_GoodBits','UL_GoodBits', ...
    'DL_Airtime_s','UL_Airtime_s','DL_Goodput_Mbps','UL_Goodput_Mbps','DL_BLER', ...
    'UL_BLER','SchedulerKpiReconciliationOk','EvidenceSource'});
T.DL_CRCObservedTrials = dlObserved;
T.UL_CRCObservedTrials = ulObserved;
T.DL_CRCUnknownTrials = dlUnknown;
T.UL_CRCUnknownTrials = ulUnknown;
T.GoodputDefinition = "unique_first_crc_success_TB_payload_over_summed_trial_exposure_not_elapsed_run_time";
T.BLERDefinition = "failed_crc_over_known_crc_all_transmission_attempts_not_residual_TB_BLER";
T.DL_DurationBasis = dlBasis;
T.UL_DurationBasis = ulBasis;
T.KPIFormulaVersion = "scheduler_transport_credit_v1";
T.KPIApplicable = applicable;
T.EvaluationStatus = "evaluated_receiver_trial_accounting";
if ~applicable, T.EvaluationStatus = "not_applicable_fixed_link_campaign_only"; end
end

function [T, bits] = localReceiverPopulation(T)
bits = zeros(0,1);
if ~istable(T) || height(T)==0, T=table(); return; end
% Preserve source credit before warmup slicing, so a later
% repeated success cannot acquire a second credit when its first is omitted.
% Normalizing the CRC representation does not turn unknown values into fails.
mask = true(height(T),1);
if ismember('FinalizedFlag', T.Properties.VariableNames)
    mask = mask & localFlag(T.FinalizedFlag)==1;
end
if ismember('FallbackFlag', T.Properties.VariableNames)
    mask = mask & localFlag(T.FallbackFlag)==0;
end
if ismember('Status', T.Properties.VariableNames)
    mask = mask & upper(strtrim(string(T.Status)))~="CRASH";
end
T=T(mask,:);
T.CRCPass = sixgr.kpi.readCRCObservations(T);
bits = sixgr.kpi.transportGoodputBits(T);
if ismember('IsWarmupFrame', T.Properties.VariableNames)
    mask=localFlag(T.IsWarmupFrame)==0;
    T=T(mask,:); bits=bits(mask);
end
end

function [rate, bits, exposure, basis] = localRate(T, credit, cfg)
rate=NaN; bits=NaN; exposure=NaN; basis="unavailable_trial_exposure";
n=height(T);
if n==0, return; end
if all(isfinite(credit)), bits=sum(credit); end
[duration,basis]=sixgr.kpi.resolveTrialExposureSeconds(T,cfg);
% Missing/zero durations must not shrink the denominator or trigger a
% fallback to planned run duration. No configured half-millisecond guess.
if isreal(duration) && numel(duration)==n && all(isfinite(duration)&duration>0)
    exposure=sum(duration);
    if isfinite(bits), rate=bits/exposure/1e6; end
end
end

function [bler,observed,unknown] = localBLER(T)
crc=sixgr.kpi.readCRCObservations(T);
observed=nnz(isfinite(crc)); unknown=nnz(~isfinite(crc)); bler=NaN;
if observed>0, bler=nnz(crc==0)/observed; end
end

function value=localFlag(value)
% Reuse the canonical three-state parser; missing is not true or false.
value=sixgr.kpi.readCRCObservations(table(value,'VariableNames',{'CRCPass'}));
end
