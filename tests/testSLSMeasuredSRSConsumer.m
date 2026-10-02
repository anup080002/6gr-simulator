function ok=testSLSMeasuredSRSConsumer()
% Pure completion-consumer fixture, not a physical SRS campaign.
cfg=struct('phy',struct('mimo',struct('measurementMaxAgeSlots',4)));
ue=struct('UEIndex',7,'ServingCell',2,'RI',1,'NumLayers',1,'PMI',3, ...
    'MUMIMOSpatialSignatureValid',true,'RankAuthority',"old_received_rank",'CQI',5);
ctx=struct('ConsumerRuntimeSlot',4,'KnownAtRuntimeSlot',3,'MaxRank',2, ...
    'ExpectedReceiveDimensions',4,'SlotDuration_s',0.001, ...
    'PhysicalExecutionID',"fixture_execution",'ChannelOwnerID',"fixture_UL_7_to_2");
signature=[1 0;0 1;0 0;0 0]/sqrt(2);
row=struct('Slot',2,'UEIndex',7,'ServingCell',2,'RIEstimate',2,'RankEstimate',NaN, ...
    'ObservationDeliverySlot',3,'ObservationStartSample',1, ...
    'ObservationEndSampleExclusive',2,'ObservationSampleRateHz',1000, ...
    'ObservationCompletionTime_s',0.002,'ObservationDeliveryTime_s',0.002, ...
    'ObservationCoverageSource',"complete_contiguous_received_sample_buffer", ...
    'ObservationDeliverySource',"canonical_slot_start_after_complete_received_window", ...
    'RuntimeTransportMode',"shared_physical_stream_SRS_received_completion", ...
    'PhysicalExecutionID',ctx.PhysicalExecutionID,'ChannelOwnerID',ctx.ChannelOwnerID, ...
    'ProxyUsed',false,'Skipped',false,'ToolboxMissing',false,'Crash',false,'UsedOracleFields',"", ...
    'DetectionAttempted',true,'DetectionSuccess',true, ...
    'ResourceExtractionAttempted',true,'ResourceExtractionAvailable',true, ...
    'ChannelEstimateAttempted',true,'SRSChannelEstimateAvailable',true,'SRSRuntimeEvidenceUsable',true, ...
    'SpatialSignatureToken',sixgr.phy.mimo.MatrixContract.serialize(signature), ...
    'SpatialSignatureSHA256',sixgr.phy.mimo.MatrixContract.digest(signature), ...
    'SpatialSignatureSource',"measured_srs_receiver_channel_estimate_dominant_rank_subspace");
[u,d]=sixgr.system.consumeSLSMeasuredSRS(ue,row,cfg,ctx);
assert(d.Applied && d.Usable && u.RI==2 && u.NumLayers==2 && isnan(u.PMI) && u.CQI==5);
assert(u.MUMIMOSpatialSignatureValid && u.SRSRankUpdateApplied);
assert(isequal(u.MUMIMOSpatialSignature,signature));
assert(u.MUMIMOSpatialSignatureSourceSlot+u.MUMIMOSpatialSignatureAgeSlots== ...
    u.MUMIMOSpatialSignatureConsumerRuntimeSlot);
assert(u.MUMIMOSpatialSignatureConsumerRuntimeSlot==(ctx.ConsumerRuntimeSlot-1)+1);
assert(string(u.MUMIMOSpatialSignatureReciprocityMode)=="direct_ul_srs");
future=ctx; future.KnownAtRuntimeSlot=2;
unchanged(ue,row,cfg,future,"srs_not_delivered_at_decision_clock");
stale=ctx; stale.ConsumerRuntimeSlot=7;
unchanged(ue,row,cfg,stale,"srs_stale_for_target_slot");
wrong=row; wrong.UEIndex=8;
unchanged(ue,wrong,cfg,ctx,"srs_identity_mismatch");
wrong=row; wrong.ServingCell=3;
unchanged(ue,wrong,cfg,ctx,"srs_identity_mismatch");
bad=row; bad.ProxyUsed=true;
unchanged(ue,bad,cfg,ctx,"srs_nonphysical_or_failed_completion");
bad=row; bad.SRSRuntimeEvidenceUsable=false;
unchanged(ue,bad,cfg,ctx,"srs_receiver_evidence_unusable");
bad=row; bad.UsedOracleFields="Htrue";
unchanged(ue,bad,cfg,ctx,"srs_oracle_fields_rejected");
bad=row; bad.RIEstimate=NaN;
unchanged(ue,bad,cfg,ctx,"srs_measured_rank_unavailable");
bad=row; bad.RIEstimate=4;
unchanged(ue,bad,cfg,ctx,"srs_rank_above_installed_capability");
unchanged(ue,table(),cfg,ctx,"no_completed_srs");
bad=row; bad.ChannelOwnerID="other_owner";
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,bad,cfg,ctx),'sixgr:system:SRSPhysicalOwnerMismatch');
bad=row; bad.PhysicalExecutionID="other_run";
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,bad,cfg,ctx),'sixgr:system:SRSPhysicalOwnerMismatch');
bad=row; bad.SpatialSignatureSHA256=string(repmat('0',1,64));
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,bad,cfg,ctx),'sixgr:mimo:PrecoderDigestMismatch');
bad=row; bad.ObservationEndSampleExclusive=3; bad.ObservationCompletionTime_s=0.003;
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,bad,cfg,ctx),'sixgr:truth:SRSResultBeforeDelivery');
bad=row; bad.SpatialSignatureSource="geometry_oracle";
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,bad,cfg,ctx),'sixgr:system:SRSSpatialAuthority');
badctx=ctx; badctx.ExpectedReceiveDimensions=2;
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,row,cfg,badctx),'sixgr:system:SRSSpatialDimensions');
codebookCfg=cfg; codebookCfg.phy.pusch.transmissionScheme='codebook';
codebookContext=ctx; codebookContext.ExpectedTransmitPorts=4;
codebookRow=row; codebookRow.ObservationID="received_srs_window_7_2";
codebookRow.SRSResourceIndicator=0; codebookRow.TPMIEstimate=0;
[u,d]=sixgr.system.consumeSLSMeasuredSRS(ue,codebookRow,codebookCfg,codebookContext);
assert(d.Applied && u.SRSValid && u.SRSCausalUsable && u.RI==2 && u.TPMI==0 && u.PMI==0);
assert(string(u.SRSCausalMeasurementId)==codebookRow.ObservationID && u.LastSuccessfulSRSSlot==2);
assert(u.SRSAgeSlots==2 && u.SRSCausalAgeSlots==2 && u.SRI==0);
staleCodebook=codebookContext; staleCodebook.ConsumerRuntimeSlot=7;
[invalid,d]=sixgr.system.consumeSLSMeasuredSRS(u,codebookRow,codebookCfg,staleCodebook);
assert(~d.Applied && ~invalid.SRSValid && ~invalid.SRSCausalUsable && invalid.RI==u.RI);
reject(@()sixgr.system.consumeSLSMeasuredSRS(ue,row,codebookCfg,codebookContext), ...
    'sixgr:system:SRSCodebookAuthority');
ok=true; fprintf('SLS_MEASURED_SRS_CONSUMER_PASS\n');
end
function unchanged(ue,row,cfg,ctx,status)
[u,d]=sixgr.system.consumeSLSMeasuredSRS(ue,row,cfg,ctx);
assert(~d.Applied && ~d.Usable && d.Status==status);
assert(u.RI==ue.RI && u.NumLayers==ue.NumLayers && u.RankAuthority==ue.RankAuthority);
assert(~u.MUMIMOSpatialSignatureValid && ~u.SRSRankUpdateApplied);
end
function reject(fn,id)
try,fn();catch ME,assert(strcmp(ME.identifier,id),'Expected %s got %s',id,ME.identifier);return;end
error('test:MissingRejection','Expected %s',id);
end
