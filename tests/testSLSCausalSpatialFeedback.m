function ok=testSLSCausalSpatialFeedback()
fragment=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
p=fragment.system.linkAbstraction.spatialFeedback; p.allowedRanks=[1 2]; p.maximumAgeSlots=4;
b=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(p);
o=struct('ObservationID',"ideal_model_0",'ExecutionID',"test_execution", ...
    'ChannelOwnerID',"UL_1_1",'UEIndex',1,'ServingCell',1, ...
    'SourceAbsoluteSlot0',0,'AvailableAbsoluteSlot0',2,'SRI',0, ...
    'ChannelEstimate',eye(2),'ExternalCovariance',eye(2), ...
    'TotalPUSCHPower',100,'ReceiverType',"lmmse",'RFProfileID',"test_rf", ...
    'EstimationAssumption',"ideal_delayed_channel_estimate", ...
    'SourceClassification',"modeled_srs_not_waveform_measurement");
b.append(o,0); b.append(o,0);
bad=o; bad.EstimationAssumption="noisy_pilot_channel_estimate";
reject(@()b.append(bad,0),'sixgr:abstraction:FeedbackSource');
assert(isempty(b.select(1,1,1,3)) && isempty(b.select(1,2,2,3)));
r=b.select(1,1,2,3); assert(r.RI==2 && r.AgeSlots==3 && ~r.WaveformBacked);
assert(abs(norm(r.MatrixPorts,'fro')-1)<1e-12);
assert(isempty(b.select(1,1,3,5))); % stale at DATA, although fresh at decision
bad=o; bad.TotalPUSCHPower=1;
reject(@()b.append(bad,0),'sixgr:abstraction:FeedbackMutation');
bad=o; bad.SourceAbsoluteSlot0=1;
reject(@()b.append(bad,0),'sixgr:abstraction:FeedbackClock');
% A rank-deficient channel selects one stream at the same total power.
weak=o; weak.ObservationID="rank_one"; weak.SourceAbsoluteSlot0=1; weak.AvailableAbsoluteSlot0=3;
weak.ChannelEstimate=[1 0;0 0]; b.append(weak,1);
r1=b.select(1,1,3,3); assert(r1.RI==1);
zf=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(p);
weak.ReceiverType="zf"; zf.append(weak,1);
rzf=zf.select(1,1,3,3); assert(rzf.RI==1);
cfg=fragment; cfg.system.linkAbstraction.spatialFeedback.enabled=true;
cfg.run.executionID='test_execution';
r.RNTI=7; r.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(r)),'UTF-8'))));
g=struct('ModeledSRSFeedback',r,'RNTI',7,'SRI',0,'ControlAbsoluteSlot',2,'ScheduledAbsoluteSlot',3);
sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant(cfg,g,2,2,r.TPMI);
badg=g; badg.TransformPrecoding=true;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant(cfg,badg,2,2,r.TPMI), ...
    'sixgr:abstraction:FeedbackWaveform');
physical=cfg; physical.system.phyBackend='waveform';
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant(physical,g,2,2,r.TPMI), ...
    'sixgr:abstraction:FeedbackBackend');
badg=g; badg.ScheduledAbsoluteSlot=4;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant(cfg,badg,2,2,r.TPMI), ...
    'sixgr:abstraction:FeedbackBinding');
badg=g; badg.ModeledSRSFeedback.RI=1;
reject(@()sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant(cfg,badg,1,2,r.TPMI), ...
    'sixgr:abstraction:FeedbackBinding');
ok=true; fprintf('SLS_CAUSAL_SPATIAL_FEEDBACK_PASS\n');
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s',id);
end
