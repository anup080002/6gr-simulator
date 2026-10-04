function ok=testSLSAggregateSRController()
r=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=sixgr.util.mergeStruct(r.Config,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/aggregate_ftp3_sr_mac.yaml'));
arrivals=table(["file_1";"file_2"],[1;3],[0;0.002],[1;1],["UL";"UL"],[80;80], ...
    'VariableNames',{'ArrivalID','ArrivalTTI','ArrivalTime_s','UEID','Direction','OfferedBits'});
files=sixgr.system.FTP3FileLedger(arrivals,0.001,1);
ledger=sixgr.system.SLSDynamicPUCCH(cfg); ledger.configureUEIdentities(4660);
controller=sixgr.system.SLSAggregateSRController(cfg,ledger,files,4660);
controller.install(1,0);
before=controller.beforeAdmission(); files.advance(1); controller.afterAdmission(0,before);
p=controller.Procedures{1}; assert(p.Pending && p.TriggerSequence==1);
g=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',0,'ScheduledAbsoluteSlot',1, ...
    'TBSBits',40,'PHYGrant',struct('IsFrozen',true), ...
    'HARQ',struct('IsRetransmission',false));
controller.receivedULGrants(g,1,0); assert(p.Pending,'A partial allocation cannot cancel SR.');
g.TBSBits=80; controller.receivedULGrants(g,1,0); assert(~p.Pending);
binding=files.bind('tb_1',1,"UL",80,1,false); assert(binding.PayloadBits==80);
% HARQ-owned payload remains queued but must not be a new-data SR trigger.
assert(files.queuedBits(1,"UL")==80 && files.unallocatedBits(1,"UL")==0);
before=controller.beforeAdmission(); files.advance(2); controller.afterAdmission(1,before);
assert(~p.Pending && p.TriggerSequence==1);
before=controller.beforeAdmission(); files.advance(3); controller.afterAdmission(2,before);
assert(p.Pending && p.TriggerSequence==2);
g.ControlAbsoluteSlot=2; g.ScheduledAbsoluteSlot=3; g.HARQ.IsRetransmission=true;
controller.receivedULGrants(g,1,2); assert(p.Pending,'Retransmission cannot cancel newly triggered SR.');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.schedulerBufferKnowledge='received_BSR';
reject(@()sixgr.system.SLSAggregateSRController(bad,ledger,files,4660), ...
    'sixgr:system:UnsupportedSRMACModel');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.trafficSchedulingRequestID=99;
reject(@()sixgr.system.SLSAggregateSRController(bad,ledger,files,4660), ...
    'sixgr:system:SRMACConfigurationMismatch');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.positiveSRSelection='transmit_all';
reject(@()sixgr.system.SLSAggregateSRController(bad,ledger,files,4660), ...
    'sixgr:system:InvalidSRSelectionPolicy');
fprintf('SLS_AGGREGATE_SR_CONTROLLER_PASS yaml_binding_arrivals_partial_full_grant_harq_isolation=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
