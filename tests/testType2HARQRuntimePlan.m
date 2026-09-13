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
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,book,frame);
assert(isa(planned.Report.Data.HARQACKReport,'sixgr.phy.pucch.HARQACKCodebookState'));
assert(planned.Report.Data.HARQACKReport.Digest==book.Digest);
serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(planned.Report);
assert(isequal(serialized.Sequence1.Bits,int8([0;1])));
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
