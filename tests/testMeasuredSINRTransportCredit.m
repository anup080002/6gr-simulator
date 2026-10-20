function ok=testMeasuredSINRTransportCredit()
% Declared receiver-table facts; no physical performance claim.
root=fullfile(pwd,'results','diagnostics','measured_sinr_credit', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
T=table(repmat("DL",3,1),ones(3,1),(1:3).',repmat("tb-one",3,1), ...
    repmat(12000,3,1),[0;1;1],[0;12000;12000],[.5;1;.5],[0;12;24], ...
    [10;15;20],repmat("OK",3,1), ...
    'VariableNames',{'Direction','UEIndex','Slot','LogicalTBID','TBSize_bits', ...
    'CRCPass','GoodBits','AirInterfaceTTI_ms','Goodput_Mbps', ...
    'PostEqSINR_dB','PostEqSINRValueStatus'});
T.OfferedBits=[12000;0;0];
T.BitsCompared=repmat(12000,3,1); T.BitErrors=[10;0;0];
r=publish(root,"weighted",T); a=aggregate(r);
assert(abs(a.Goodput_Mbps-6)<1e-12&&abs(a.RadioDuration_s-.002)<1e-15, ...
    'test:MeasuredSINRDoubleCredit','Summary must credit 12000 bits once over 2 ms.');
assert(a.GoodputDefinition=="unique_first_crc_success_TB_payload_over_summed_trial_exposure_not_elapsed_run_time");
changed=T; changed.GoodBits(:)=99999; changed.Goodput_Mbps(:)=999;
b=aggregate(publish(root,"poisoned_rates",changed));
assert(b.Goodput_Mbps==a.Goodput_Mbps);
% An unmeasurable SINR does not transfer the original payload credit to a
% later duplicate that happens to have a usable measurement.
changed=T; changed.PostEqSINR_dB(2)=NaN;
r=publish(root,"missing_first_sinr",changed); b=aggregate(r);
assert(b.Goodput_Mbps==0&&all(r.Tables.DLThroughputCurve.Goodput_Mbps_mean==0));
% Receiver-derived CRC missing is not repaired with GoodBits or TB size.
changed=T; changed.CRCPass(2)=NaN;
b=aggregate(publish(root,"unknown_crc",changed));
assert(isnan(b.Goodput_Mbps)&&~b.StrictOk);
changed=T; changed.AirInterfaceTTI_ms(2)=NaN;
b=aggregate(publish(root,"unknown_duration",changed));
assert(isnan(b.Goodput_Mbps)&&isnan(b.RadioDuration_s)&&~b.StrictOk);
% Row rate statistics are explicitly separate from aggregate bit/time rates.
r=publish(root,"row_statistics",T);
s=r.Tables.Summary(r.Tables.Summary.UEIndex=="all",:);
assert(s.Goodput_Mbps_mean==4&&contains(s.GoodputDefinition,"per_trial_rates"));
missing=removevars(T,'LogicalTBID');
b=aggregate(publish(root,"unknown_identity",missing));
assert(isnan(b.Goodput_Mbps)&&~b.StrictOk);
ok=true;
end
function r=publish(root,tag,T)
r=sixgr.analytics.generateMeasuredSINRCurves(fullfile(root,tag),tag, ...
    'TrialData',struct('DL',T),'ScenarioConfig',struct(), ...
    'UpdateAnchorKPIs',false);
end
function T=aggregate(r)
T=r.Tables.KPISummary(r.Tables.KPISummary.UEIndex=="all",:);
end
