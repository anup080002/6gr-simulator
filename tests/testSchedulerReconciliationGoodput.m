function ok=testSchedulerReconciliationGoodput()
% Declared receiver facts, not physical or statistical observations.
cfg=sixgr.config.defaultConfig();
root=fullfile(pwd,'results','diagnostics','scheduler_reconciliation', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
T=table(repmat("DL",3,1),ones(3,1),(1:3).',repmat("tb-one",3,1), ...
    [12000;12000;12000],[0;1;1],[0;12000;0],[0.5;1;0.5],[0;12;0], ...
    'VariableNames',{'Direction','UEIndex','Slot','LogicalTBID','TBSize_bits', ...
    'CRCPass','GoodBits','AirInterfaceTTI_ms','Goodput_Mbps'});
T=sixgr.kpi.creditTransportGoodput(T);
a=write(cfg,root,"weighted",T);
assert(a.DL_GoodBits==12000&&abs(a.DL_Airtime_s-.002)<1e-15&& ...
    abs(a.DL_Goodput_Mbps-6)<1e-12,'test:UnweightedSchedulerGoodput', ...
    'Expected 12000 bits / 2 ms = 6 Mbps, not the mean of per-attempt rates.');
assert(a.GoodputDefinition=="unique_first_crc_success_TB_payload_over_summed_trial_exposure_not_elapsed_run_time");
% A stale/poisoned per-row rate must not override authoritative bit/time sums.
changed=T; changed.Goodput_Mbps(:)=999;
b=write(cfg,root,"poisoned_rate",changed);
assert(b.DL_Goodput_Mbps==a.DL_Goodput_Mbps);
% An older raw table can derive credit only from actual logical TB identity.
names=string(T.Properties.VariableNames);
credit=startsWith(names,"TransportGoodput")|ismember(names,["UniqueDeliveredTBBits","FirstSuccessfulTBDelivery"]);
legacy=removevars(T,names(credit)); legacy.GoodBits=[0;12000;12000];
b=write(cfg,root,"repeated_success",legacy); assert(b.DL_GoodBits==12000);
missing=removevars(legacy,'LogicalTBID');
b=write(cfg,root,"missing_identity",missing);
assert(isnan(b.DL_GoodBits)&&isnan(b.DL_Goodput_Mbps)&&~b.SchedulerKpiReconciliationOk);
changed=T; changed.AirInterfaceTTI_ms(2)=NaN;
b=write(cfg,root,"partial_duration",changed);
assert(isnan(b.DL_Airtime_s)&&isnan(b.DL_Goodput_Mbps)&&~b.SchedulerKpiReconciliationOk);
changed=T; changed.AirInterfaceTTI_ms(2)=0;
b=write(cfg,root,"zero_duration",changed);
assert(isnan(b.DL_Goodput_Mbps)&&~b.SchedulerKpiReconciliationOk);
% Preserve original online zero credit when the first success is outside a slice.
b=write(cfg,root,"duplicate_slice",T(3,:));
assert(b.DL_GoodBits==0&&b.DL_Goodput_Mbps==0);
% The same older raw logical TB cannot be delivered again after warmup.
changed=legacy; changed.IsWarmupFrame=[true;true;false];
b=write(cfg,root,"warmup_identity",changed);
assert(b.DL_GoodBits==0&&b.DL_Goodput_Mbps==0);
changed=T; changed.FinalizedFlag=false(3,1);
b=write(cfg,root,"all_pending",changed);
assert(b.DL_GrantCount==0&&isnan(b.DL_Goodput_Mbps)&&~b.SchedulerKpiReconciliationOk);
% Missing duration is not an implicit 30-kHz numerology.
changed=removevars(T,'AirInterfaceTTI_ms');
b=write(struct(),root,"no_time_authority",changed);
assert(isnan(b.DL_Airtime_s)&&~b.SchedulerKpiReconciliationOk);
b=write(struct('frame_timing',struct('scs_khz',60)),root,"explicit_scs",changed);
assert(abs(b.DL_Airtime_s-.00075)<1e-15&&b.DL_Goodput_Mbps==16);
ok=true;
end
function T=write(cfg,root,tag,dl)
ul=dl; ul.Direction(:)="UL";
if ismember('UniqueDeliveredTBBits',ul.Properties.VariableNames)
    % Independent fixture direction needs its own real identity-scoped credit.
    ul=sixgr.kpi.creditTransportGoodput(ul);
end
a=sixgr.analytics.writeRFInterferenceReconciliation(cfg,fullfile(root,tag), ...
    struct('DL',dl,'UL',ul),struct(),struct());
T=a.Tables.Scheduler;
end
