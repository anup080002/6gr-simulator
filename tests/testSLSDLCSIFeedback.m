function ok=testSLSDLCSIFeedback()
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run.executionID='dl_csi_component';
cfg.system.linkAbstraction.dlFeedback.enabled=true;
cfg.system.linkAbstraction.dlFeedback.panel.Ports=2;
cfg.system.linkAbstraction.dlFeedback.maximumAgeSlots=8;
cfg.phy.csi.cqiTable='table1';
% Explicit existing CQI lab mapping, not a qualification of its thresholds.
cfg.phy.csi.allowUncalibratedBLERLUT=true;
q=sixgr.system.abstraction.CausalDLCSIFeedback(cfg);
o=struct('ObservationID',"a",'ExecutionID',"dl_csi_component",'UEIndex',1,'ServingCell',1, ...
    'SourceAbsoluteSlot0',0,'AvailableAbsoluteSlot0',2,'CRI',0, ...
    'ChannelEstimate',repmat(eye(2),1,1,4),'ExternalCovariance',eye(2), ...
    'TotalTransmitPower',100,'RFProfileID',"ideal",'SourceClassification',"modeled_csi_not_waveform_measurement");
q.append(o,0); assert(isempty(q.select(1,1,1,2)));
r=q.select(1,1,2,3); assert(r.RI==2 && abs(norm(r.MatrixPorts,'fro')-1)<1e-12);
old=r; q.append(o,1); assert(isequaln(q.select(1,1,2,3),r));
bad=o; bad.ChannelEstimate=2*bad.ChannelEstimate;
reject(@()q.append(bad,1),'sixgr:abstraction:DLCSIMutation');
o.ObservationID="b"; o.SourceAbsoluteSlot0=2; o.AvailableAbsoluteSlot0=4;
o.ChannelEstimate=repmat([1 1;1 1],1,1,4); q.append(o,2);
assert(isequaln(q.select(1,1,2,3),old));
new=q.select(1,1,4,5); assert(new.RI==1 && old.RI==2);
new.RNTI=1;
new.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(new)),'UTF-8'))));
g=struct('ModeledCSIFeedback',new,'RNTI',1,'ServingCell',1,'NumLayers',new.RI,'PMI',new.PMI, ...
    'ControlAbsoluteSlot',4,'ScheduledAbsoluteSlot',5,'HARQ',struct('IsRetransmission',false));
sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(cfg,g);
bad=g; bad.ModeledCSIFeedback.MatrixPorts=2*new.MatrixPorts;
reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(cfg,bad),'sixgr:abstraction:DLCSIBinding');
bad=g; bad.ControlAbsoluteSlot=3;
reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(cfg,bad),'sixgr:abstraction:DLCSIBinding');
waveform=cfg; waveform.system.phyBackend='waveform';
reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(waveform,g),'sixgr:abstraction:DLCSIBinding');
assert(isempty(q.select(1,2,4,5)) && isempty(q.select(1,1,11,11)));
fprintf('SLS_DL_CSI_CAUSAL_CODEBOOK_PASS\n'); ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'%s: %s',ME.identifier,ME.message); return; end
error('test:NoRejection','Expected %s',id);
end
