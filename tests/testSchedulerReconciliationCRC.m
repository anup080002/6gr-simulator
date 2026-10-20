function ok=testSchedulerReconciliationCRC()
% Missing/invalid CRC is not a measured failed block.
cfg=sixgr.config.defaultConfig();
root=fullfile(pwd,'results','diagnostics','scheduler_crc', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
T=table(repmat("DL",3,1),ones(3,1),(1:3).',"tb-"+(1:3).', ...
    repmat(800,3,1),[1;NaN;0],[800;NaN;0],repmat(.5,3,1), ...
    'VariableNames',{'Direction','UEIndex','Slot','LogicalTBID','TBSize_bits', ...
    'CRCPass','GoodBits','AirInterfaceTTI_ms'});
a=write(cfg,root,"unknown",T);
assert(abs(a.DL_BLER-.5)<1e-12,'test:UnknownCRCCountedAsFailure', ...
    'One known fail among two known CRCs is 0.5; the unknown CRC is separate.');
assert(a.DL_CRCObservedTrials==2&&a.DL_CRCUnknownTrials==1&& ...
    ~a.SchedulerKpiReconciliationOk&&isnan(a.DL_Goodput_Mbps));
for value=[2,-1,Inf]
    changed=T; changed.CRCPass(2)=value;
    b=write(cfg,root,"invalid_"+string(value),changed);
    assert(b.DL_BLER==.5&&b.DL_CRCUnknownTrials==1&&~b.SchedulerKpiReconciliationOk);
end
T.CRCPass(:)=NaN;
b=write(cfg,root,"all_unknown",T);
assert(isnan(b.DL_BLER)&&b.DL_CRCObservedTrials==0&&b.DL_CRCUnknownTrials==3);
ok=true;
end
function T=write(cfg,root,tag,dl)
ul=dl; ul.Direction(:)="UL";
a=sixgr.analytics.writeRFInterferenceReconciliation(cfg,fullfile(root,tag), ...
    struct('DL',dl,'UL',ul),struct(),struct());
T=a.Tables.Scheduler;
end
