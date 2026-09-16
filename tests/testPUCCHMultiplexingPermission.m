function ok=testPUCCHMultiplexingPermission()
% Installed higher-layer authority; no RF episode or qualification claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(s.Data.pucch_resources.format2.simultaneous_harq_ack_csi,true) && ...
    isequal(cfg.validation.pucch_resources.format2.simultaneous_harq_ack_csi,true));
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
frame=struct('K1',1,'K1Source','decoded_dci','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','declared_test_DCI', ...
    'FirstCCE',0,'NumCCE',8,'SlotSymbolOwnership',"UUUUUUUUUUUUUU", ...
    'FlexibleResolutionProvided',false);
% This scenario installs SR on the same occasion. An explicitly idle UE
% procedure still contributes the configured negative long-format SR bit.
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,3);
h=int8([1;0]); c=int8([0;1;0;1]);
tx=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,h,c,int8([]),frame);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
% Receiver declaration precedes no TX-derived schema handoff.
context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"permission_rx", ...
    'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',7,'Sequence2Length',0, ...
    'HARQACKBits',2,'SRBits',1,'CSIPart1Bits',4,'CSIPart2Bits',0,'PriorityIndex',0));
identity=struct('ObservationID',"permission_rx",'ResourceID',10,'RNTI',1, ...
    'AbsoluteSlot0',3,'Source',"declared_gNB_obligation",'TimingSource',"configured_test", ...
    'ResourceSelectionProcedure',"dynamic_harq_csi");
rx=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,rrc,context);
assert(tx.Plan.RRCContextDigest==rx.RRCContextDigest && ...
    tx.Plan.Resource.ID==rx.Resource.ID && rrc.allowsHARQCSI(2));
assert(tx.ReceiverContext.SRBits==context.SRBits && ...
    tx.ReceiverContext.Sequence1Length==context.Sequence1Length && ...
    isequal(tx.Report.Data.SchedulingRequestReports.Bits,int8(0)));
assert(~rrc.allowsHARQCSI(3) && ~rrc.allowsHARQCSI(4));
for supplied=[false true]
    denied=cfg;
    if supplied
        denied.validation.pucch_resources.format2.simultaneous_harq_ack_csi=false;
    else
        denied.validation.pucch_resources.format2=rmfield(denied.validation.pucch_resources.format2, ...
            'simultaneous_harq_ack_csi');
    end
    deniedRRC=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(denied,ue);
    assert(~deniedRRC.allowsHARQCSI(2) && deniedRRC.Digest~=rrc.Digest);
    reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCombined( ...
        denied,ue,h,c,int8([]),frame),'sixgr:phy:pucch:HARQCSIMultiplexingNotConfigured');
    reject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(identity,deniedRRC,context), ...
        'sixgr:phy:pucch:HARQCSIMultiplexingNotConfigured');
    % Denying multiplexing does not disable either standalone report.
    harq=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(denied,ue,h,frame);
    csi=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(denied,ue,c,int8([]),frame);
    assert(harq.Plan.Resource.ID==0 && csi.Plan.Resource.ID==10);
end
for value={NaN,Inf,-1,2,[],[true false],"false",struct()}
    bad=cfg;
    bad.validation.pucch_resources.format2.simultaneous_harq_ack_csi=value{1};
    reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
        'sixgr:phy:pucch:InvalidMultiplexingPermission');
end
% A malformed typed context must not bypass the YAML-facing boundary.
bad=rrc.Data; bad.FormatConfigurations.SimultaneousHARQACKCSI="true";
reject(@()sixgr.phy.pucch.PUCCHRRCContext(bad),'sixgr:phy:pucch:InvalidMultiplexingPermission');
bad=rrc.Data; bad.SimultaneousHARQACKCSI=true;
reject(@()sixgr.phy.pucch.PUCCHRRCContext(bad),'sixgr:phy:pucch:InvalidMultiplexingPermission');
bad=cfg; bad.validation.pucch_resources.simultaneous_harq_ack_csi=true;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
    'sixgr:phy:pucch:InvalidMultiplexingPermission');
bad=rrc.Data; bad.FormatConfigurations=[bad.FormatConfigurations bad.FormatConfigurations];
reject(@()sixgr.phy.pucch.PUCCHRRCContext(bad),'sixgr:phy:pucch:InvalidMultiplexingPermission');
% Permission follows the selected resource's format, not another format's IE.
for format=2:4
    mixed=rrc.Data;
    mixed.FormatConfigurations=struct('Format',{2,3,4}, ...
        'SimultaneousHARQACKCSI',{true,false,true},'MaxCodeRate',{0.35,0.35,0.35});
    index=find([mixed.Resources.ID]==identity.ResourceID);
    mixed.Resources(index).Format=format;
    if format>=3
        mixed.Resources(index).NumSymbols=4; mixed.Resources(index).StartSymbol=10;
    end
    if format==4, mixed.Resources(index).NumPRBs=1; end
    mixedRRC=sixgr.phy.pucch.PUCCHRRCContext(mixed);
    ueWithEpoch=ue; ueWithEpoch.ConfigurationEpoch=rrc.ConfigurationEpoch;
    if format==3
        reject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(identity,mixedRRC,context), ...
            'sixgr:phy:pucch:HARQCSIMultiplexingNotConfigured');
        reject(@()sixgr.phy.pucch.PUCCHResourcePlan(tx.Report,ueWithEpoch,mixedRRC,frame,"component"), ...
            'sixgr:phy:pucch:HARQCSIMultiplexingNotConfigured');
    else
        rxMixed=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,mixedRRC,context);
        txMixed=sixgr.phy.pucch.PUCCHResourcePlan(tx.Report,ueWithEpoch,mixedRRC,frame,"component");
        assert(rxMixed.Format==format && txMixed.Format==format);
    end
end
ok=true;
fprintf('PUCCH_MULTIPLEXING_PERMISSION_PASS per_format_TX_RX_authority=1 mixed_format_isolation=1 absent_false_global_duplicate_rejected=1 RF_episodes=0\n');
end

function reject(fn,id)
try
    fn();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error: %s',err.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
