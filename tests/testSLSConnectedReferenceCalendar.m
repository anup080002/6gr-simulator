function ok=testSLSConnectedReferenceCalendar()
% Native resources and configured obligations; not decoded CSI/SRS/UCI.
request=sixgr.config.loadSimulationRequest( ...
    'simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=request.Config;
assert(isequal(cfg.phy.csirs.precoderMatrices,eye(4)) && ...
    cfg.channel.nTxAnt==4 && cfg.channel.nRxAnt==4, ...
    'Direct-port CSI-RS and channel dimensions must not collapse with data rank.');
assert(isequal(cfg.phy.csi.reportConfiguration.AllowedRanks,[1 2 4]));
for invalid={[2 1 4],[1 1 4],[1 2 5]}
    bad=cfg.phy.csi.reportConfiguration;
    bad.AllowedRanks=invalid{1};
    rejected=false;
    try
        sixgr.phy.mimo.CSIReportConfiguration(bad,cfg.phy.csi.reportConfigurationEpoch);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:mimo:InvalidRI'),'%s',cause.message);
        rejected=true;
    end
    assert(rejected,'Invalid CSI ranks must not be sorted, deduplicated or clipped.');
end
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
report=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
report.assertQualifiedWireLayout();
assert(isequal(report.AllowedRanks,[1 2 4]) && report.Ports==4);
carrier=sixgr.phy.grid.makeCarrier(cfg);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(isequal(strict.ToolboxSRS.SRSPeriod,[20 9]) && strict.ToolboxSRS.NumSRSPorts==4);
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
assert(isempty(rrc.Data.SPSPUCCHANResources),'No DL SPS resource is installed by this scenario.');
for name=["sr_resource_ids","csi_resource_ids","sps_pucch_an_resource_ids"]
    emptyCfg=cfg; emptyCfg.validation.pucch_resources.(name)=[];
    sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(emptyCfg,ue);
    missingCfg=cfg; missingCfg.validation.pucch_resources=rmfield(missingCfg.validation.pucch_resources,name);
    rejected=false;
    try
        sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(missingCfg,ue);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:phy:pucch:StaleConfiguration'),'%s',cause.message);
        rejected=true;
    end
    assert(rejected,'An absent resource-list declaration must not become an explicitly empty installed list.');
end
[reports,~]=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,80);
sr=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,80);
assert(isequal(reports.ReportSlot.',[10 30 50 70]) && all(reports.ULResourceAvailable));
assert(isequal(sr.Slot.',[10 30 50 70]) && all(sr.ULResourceAvailable));
for slot=0:79
    c=carrier; c.NSlot=mod(slot,c.SlotsPerFrame); c.NFrame=floor(slot/c.SlotsPerFrame);
    variant=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot+1);
    [indices,symbols,info,rs]=sixgr.phy.refsig.csirs(c,variant);
    due=mod(slot-1,20)==0;
    assert(logical(info.Scheduled)==due);
    if due
        assert(~isempty(symbols) && ~isempty(indices) && rs.NumCSIRSPorts==4 && ...
            frame.IsDLAllocation(slot,[rs.SymbolLocations,1]));
        match=find(reports.ReportSlot==slot+9);
        assert(isscalar(match) && reports.CSIReferenceSlot(match)>=slot+1);
    else
        assert(isempty(symbols) && isempty(indices),'CSI-RS must not reserve non-occasion REs.');
    end
    if mod(slot-9,20)==0
        s=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal( ...
            c,'SRS',strict.ToolboxSRS,'AbsoluteSlot',slot);
        coords=double(s.ActualCoordinates0Based);
        assert(~isempty(coords) && all(coords(:,2)==13) && frame.IsULAllocation(slot,[13 1]));
        for resource=reshape(rrc.Resources,1,[])
            p=sixgr.phy.frame.ChannelAllocationMaterializer.materializePUCCH( ...
                c,resource.toolboxConfig(),'AbsoluteSlot',slot);
            assert(isempty(intersect(coords(:,1:2),double(p.ActualCoordinates0Based(:,1:2)),'rows')), ...
                'Configured SRS and PUCCH must not double-own the same UL REs.');
        end
    end
end
assert(any(contains(request.SourceFiles,'scheduling_request_periods_r18.yaml')));
fprintf('SLS_CONNECTED_REFERENCE_CALENDAR_PASS slots=80 CSI_SRS_ports=4 decoded_feedback=0\n');
ok=true;
end
