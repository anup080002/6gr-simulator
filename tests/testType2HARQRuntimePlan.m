function ok=testType2HARQRuntimePlan()
% Required consumer gate: typed DAI codebook must retain identity through the
% actual YAML-resolved PUCCH resource planner. No receive/TX power is invented.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
epoch=cfg.validation.pucch_resources.configuration_epoch;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'harq');
frame=struct('K1',1,'K1Source','decoded_dci','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',pri.PRIValue,'PRIFieldWidth',3, ...
    'PRIProvenance',pri.Source,'FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU",'FlexibleResolutionProvided',false, ...
    'TriggeringEventID',"type2_received_procedure_fixture");
e=struct('DAI',2,'EventIndex',1,'PDSCHID',"decoded-PDSCH",'Priority',0, ...
    'ServingCell',1,'State',"ACK",'ConfigurationEpoch',epoch,'TargetSlot',4,'RNTI',1);
book=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',e,epoch);
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,book,frame), ...
    'sixgr:truth:MissingSRProcedureState');
% The installed SR procedure is explicitly idle, not absent. Negative SR on
% this short-format resource must not change the original HARQ payload.
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,3);
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,book,frame);
assert(isa(planned.Report.Data.HARQACKReport,'sixgr.phy.pucch.HARQACKCodebookState'));
assert(planned.Report.Data.HARQACKReport.Digest==book.Digest);
serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(planned.Report);
% Serialization retains the separate SR indication for the short-format
% cyclic-shift procedure. It is not an additional HARQ information bit.
owners=serialized.Sequence1.Owners;
harqBits=serialized.Sequence1.Bits(owners=="HARQ_ACK");
srBits=serialized.Sequence1.Bits(owners=="SR");
assert(isequal(harqBits,int8([0;1])));
assert(isequal(owners,["HARQ_ACK";"HARQ_ACK";"SR"]) && ...
    isequal(serialized.Sequence1.Bits,int8([0;1;0])) && isequal(srBits,int8(0)));
assert(planned.Plan.Format==0 && planned.Plan.Data.ResourceSetID==0 && ...
    planned.ReceiverContext.HARQACKBits==2 && planned.ReceiverContext.SRBits==1);
carrier=sixgr.phy.grid.makeCarrier(sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,frame.TargetSlot));
pucch=planned.Plan.Resource.toolboxConfig();
negative=nrPUCCH(carrier,pucch,{harqBits,srBits});
harqOnly=nrPUCCH(carrier,pucch,{harqBits,int8([])});
positive=nrPUCCH(carrier,pucch,{harqBits,int8(1)});
assert(isequal(negative,harqOnly) && ~isequal(negative,positive), ...
    'Negative SR preserves Format-0 HARQ symbols; positive SR has distinct cyclic-shift meaning.');
assert(planned.Plan.Data.DueSlot==4 && ~isfield(planned,'Assignment'));
wrong=e; wrong.TargetSlot=5;
wrong=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',wrong,epoch);
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,wrong,frame), ...
    'sixgr:phy:pucch:MixedHARQContext');
wrong=e; wrong.RNTI=2;
wrong=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',wrong,epoch);
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,wrong,frame), ...
    'sixgr:phy:pucch:MixedHARQContext');
wrong=e; wrong.UEId=2;
wrong=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',wrong,epoch);
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,wrong,frame), ...
    'sixgr:phy:pucch:MixedHARQContext');
% A PUSCH-specific procedure cannot silently change a PUCCH payload length.
wrong=sixgr.phy.pucch.HARQACKCodebookState(book.CodebookType,book.Events,epoch, ...
    book.SourceEventIndex,struct('Transport',"PUSCH"));
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,wrong,frame), ...
    'sixgr:phy:pucch:UnsupportedHARQCodebook');
fprintf('TYPE2_HARQ_RUNTIME_PLAN_PASS\n'); ok=true;
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
