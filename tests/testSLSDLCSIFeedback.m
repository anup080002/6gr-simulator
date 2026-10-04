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
resolved=sixgr.system.PhyFactory.resolveConfig(waveform, ...
    struct('PHYBackend','calibrated_link_abstraction'));
sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(resolved,g);
assert(strcmp(waveform.system.phyBackend,'waveform'),'Do not mutate caller configuration.');
reject(@()sixgr.system.PhyFactory.resolveConfig(cfg,struct('PHYBackend','lut')), ...
    'sixgr:system:ProxyBackendRemoved');
reject(@()sixgr.system.PhyFactory.resolveConfig(cfg,struct('PHYBackend',["waveform","calibrated_link_abstraction"])), ...
    'sixgr:system:UnsupportedPHYBackend');
% A runtime backend override must not leave modeled-feedback authority in
% the physical executor's configuration.
phy=sixgr.system.PhyFactory.create(cfg,struct('PHYBackend','waveform'));
assert(strcmpi(string(phy.Cfg.system.phyBackend),'waveform'), ...
    'test:WaveformBackendAuthority','Waveform executor retained abstraction authority.');
reject(@()phy.decode(struct('Grant',g,'Direction','DL')), ...
    'sixgr:system:WaveformReplay:ModeledFeedback');
reject(@()sixgr.system.waveform.replayGrant(cfg,'DL',g,[],20), ...
    'sixgr:system:WaveformReplay:ModeledFeedback');
frozen=struct('PHYGrant',struct('PrecodingState', ...
    struct('ModeledCSIFeedback',new,'ModeledCSIDecisionUsed',true)));
phy.LongRunAuditEnabled=true; phy.LongRunAuditPeriodSlots=10;
reject(@()phy.decode(struct('Grant',frozen,'Direction','DL','TTI',2)), ...
    'sixgr:system:WaveformReplay:ModeledFeedback');
sixgr.system.waveform.assertPhysicalFeedbackAuthority(struct('ModeledCSIFeedback',struct()));
assert(isempty(q.select(1,2,4,5)) && isempty(q.select(1,1,11,11)));
% Native-emission provenance must survive rank/PMI selection and binding.
% This declared identity fixture tests the consumer; it is not PHY evidence.
emitted=cfg;
emitted.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs_and_csirs';
emitted.phy.csirs.resourceIDs=7;
eq=sixgr.system.abstraction.CausalDLCSIFeedback(emitted);
reject(@()eq.append(o,2),'sixgr:abstraction:DLCSIEmissionBinding');
o.ReferenceResourceID=7;
o.ReferenceEmissionSHA256=string(sixgr.util.sha256Hex(uint8('explicit_emission_binding_test_fixture')));
eq.append(o,2); er=eq.select(1,1,4,5);
assert(er.ReferenceResourceID==7 && er.ReferenceEmissionSHA256==o.ReferenceEmissionSHA256);
er.RNTI=1;
er.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(er)),'UTF-8'))));
eg=g; eg.ModeledCSIFeedback=er;
sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(emitted,eg);
bad=o; bad.ObservationID="wrong_native_resource"; bad.ReferenceResourceID=19;
reject(@()eq.append(bad,2),'sixgr:abstraction:DLCSIEmissionBinding');
bad=eg; bad.ModeledCSIFeedback=rmfield(er,'ReferenceEmissionSHA256');
reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(emitted,bad), ...
    'sixgr:abstraction:DLCSIEmissionBinding');
% Adding PDCCH/SSB must not disable the CSI emission identity guard.
extended=emitted;
extended.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs_and_csirs_and_pdcch';
for withSSB=[false true]
    extended.system.linkAbstraction.networkSpatial.ssbInterferenceEnabled=withSSB;
    eq=sixgr.system.abstraction.CausalDLCSIFeedback(extended);
    missing=rmfield(o,'ReferenceEmissionSHA256');
    reject(@()eq.append(missing,2),'sixgr:abstraction:DLCSIEmissionBinding');
    eq.append(o,2);
    sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(extended,eg);
    reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(extended,bad), ...
        'sixgr:abstraction:DLCSIEmissionBinding');
end
fprintf('SLS_DL_CSI_CAUSAL_CODEBOOK_PASS\n'); ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'%s: %s',ME.identifier,ME.message); return; end
error('test:NoRejection','Expected %s',id);
end
