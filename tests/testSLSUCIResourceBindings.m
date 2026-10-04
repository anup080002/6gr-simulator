function ok=testSLSUCIResourceBindings()
% Installed reservations plus isolated offset-BWP waveform round trips.
% Neither test calibration nor these two waveforms qualify network UCI.
r=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=r.Config;
registry=sixgr.system.SLSUCIResourceBindings(cfg);
serving=repmat((1:21).',10,1);
registry.update(serving,0,zeros(0,2));
assert(height(registry.Trace)==210 && ~any(registry.Trace.WaveformBacked));
id=cfg.phy.frame.DefaultIdentity;
ue=@(u,c)struct('UEID',u,'RNTI',u,'ServingCell',c,'PUCCHCell',c, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
a=registry.configForUE(ue(1,1)); b=registry.configForUE(ue(22,1));
ra=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(a,ue(1,1));
rb=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(b,ue(22,1));
ar=ra.resourceByID(0); br=rb.resourceByID(0);
assert(ar.Data.StartPRB~=br.Data.StartPRB);
assert(isequal([ra.Resources.ID],[rb.Resources.ID]) && ra.Digest~=rb.Digest);
% A real protocol identity need not equal its internal resource-owner index.
mapped=sixgr.system.SLSUCIResourceBindings(cfg);
mapped.configureUEIdentities(4660);
mapped.update(1,0,zeros(0,2));
mappedUE=ue(1,1); mappedUE.RNTI=4660;
mappedCfg=mapped.configForUE(mappedUE);
mappedRRC=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(mappedCfg,mappedUE);
assert(mapped.Trace.RNTI==4660 && mapped.Trace.UEIndex==1 && mapped.Trace.RRCContextDigest==mappedRRC.Digest);
reject(@()mapped.configForUE(ue(1,1)),'sixgr:system:MissingUCIResourceBinding');
original=ra.Digest; registry.update(serving,1,zeros(0,2));
again=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(registry.configForUE(ue(1,1)),ue(1,1));
assert(again.Digest==original && height(registry.Trace)==210,'Polling must not reassign resources or create epochs.');
% Protected ownership cannot be recycled while another user is admitted.
small=cfg; small.system.linkAbstraction.dynamicPUCCH.resourceBinding.capacityPerCell=2;
q=sixgr.system.SLSUCIResourceBindings(small); q.update([1;2],0,zeros(0,2));
before=q.Trace;
reject(@()q.update([2;2;2],1,zeros(0,2)),'sixgr:system:UCIResourcePoolExhausted');
assert(isequal(q.Trace,before),'Failed admission must leave every installed lease unchanged.');
q.update([2;2],1,[1 1]);
old=q.configForUE(ue(1,1)); assert(old.validation.pucch_resources.resources(1).starting_prb==0);
q.update([2;2],2,zeros(0,2));
reject(@()q.configForUE(ue(1,1)),'sixgr:system:MissingUCIResourceBinding');
assert(any(q.Trace.Action=="released"));
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.resourceBinding.stridePRB=4;
reject(@()sixgr.system.SLSUCIResourceBindings(bad),'sixgr:system:UCIResourcePoolGrid');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.resourceBinding.capacityPerCell=55;
reject(@()sixgr.system.SLSUCIResourceBindings(bad),'sixgr:system:UCIResourcePoolGrid');
% Production ledger creates SR obligations for all 210 UEs. Native RE maps
% must be disjoint within each cell; resources may be reused across cells.
cfg.phy.csi.reportCSI=false;
ledger=sixgr.system.SLSDynamicPUCCH(cfg);
o=ledger.snapshot(9,9,serving,struct([]));
assert(numel(o)==210 && all([o.SRBits]==1) && all([o.HARQBits]==0));
for c=1:21
    current=o([o.CellID]==c); allRE=zeros(0,2);
    for k=1:numel(current)
        allRE=[allRE;unique(current(k).Coordinates0Based(:,1:2),'rows')]; %#ok<AGROW>
    end
    assert(size(unique(allRE,'rows'),1)==size(allRE,1));
end
ledger.completeSlot(9,serving,struct([]),{},struct([]));
assert(height(ledger.CompletionTrace)==210 && ~any(ledger.CompletionTrace.WaveformBacked));
% Nonzero carrier AND BWP origins: do not confuse CRB, carrier PRB and
% BWP-relative resource coordinates. Native data/DMRS must map each hop.
shifted=cfg; shifted.phy.carrier.NStartGrid=7;
shifted.system.linkAbstraction.dynamicPUCCH.resourceBinding.capacityPerCell=2;
ccIndex=find([shifted.phy.frame.ComponentCarriers.CCID]==id.ScheduledCCID);
bwps=shifted.phy.frame.ComponentCarriers(ccIndex).BWPs;
bi=find([bwps.BWPID]==id.ULBWPID & upper(string({bwps.Direction}))=="UL");
shifted.phy.frame.ComponentCarriers(ccIndex).BWPs(bi).NStartBWP=20;
shifted.phy.frame.ComponentCarriers(ccIndex).BWPs(bi).NSizeBWP=120;
shiftedRegistry=sixgr.system.SLSUCIResourceBindings(shifted);
shiftedRegistry.update([1;1],0,zeros(0,2));
projected=shiftedRegistry.configForUE(ue(1,1));
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(projected,ue(1,1));
carrier=nrCarrierConfig('NStartGrid',7,'NSizeGrid',shifted.phy.carrier.NSizeGrid, ...
    'SubcarrierSpacing',shifted.phy.carrier.SubcarrierSpacing);
for k=1:numel(rrc.Resources)
    d=rrc.Resources(k).Data;
    assert(d.NStartBWP==20 && d.NSizeBWP==120);
    for hopping=[false true]
        if hopping && d.NumSymbols<2, continue; end
        d.IntraSlotHopping=hopping; d.SecondHopStartPRB=100;
        resource=sixgr.phy.pucch.PUCCHResource(d); native=resource.toolboxConfig();
        assert(native.NStartBWP==20 && native.NSizeBWP==120 && native.PRBSet(1)==d.StartPRB);
        indices=[nrPUCCHIndices(carrier,native);nrPUCCHDMRSIndices(carrier,native)];
        [sc,sym]=ind2sub([12*carrier.NSizeGrid carrier.SymbolsPerSlot],double(indices));
        start=repmat(d.StartPRB,numel(indices),1);
        if hopping, start(sym-1>=d.StartSymbol+floor(d.NumSymbols/2))=100; end
        prb=floor((sc-1)/12);
        assert(all(prb>=13+start & prb<13+start+d.NumPRBs), ...
            'Native PUCCH/DMRS indices lost the BWP-to-carrier offset or hop.');
    end
end
shiftedLedger=sixgr.system.SLSDynamicPUCCH(shifted);
shiftedObligations=shiftedLedger.snapshot(9,9,[1;1],struct([]));
baseLedger=sixgr.system.SLSDynamicPUCCH(cfg);
baseObligations=baseLedger.snapshot(9,9,[1;1],struct([]));
assert(numel(shiftedObligations)==2 && numel(baseObligations)==2);
for k=1:2
    expected=baseObligations(k).Coordinates0Based; expected(:,1)=expected(:,1)+12*13;
    assert(isequal(shiftedObligations(k).Coordinates0Based,expected), ...
        'Production UCI reservation must shift by the executed BWP origin.');
end
bad=shifted; bad.phy.frame.ComponentCarriers(ccIndex).BWPs(bi).NStartBWP=6;
reject(@()sixgr.system.SLSUCIResourceBindings(bad),'sixgr:system:UCIResourcePoolGrid');
bad=projected; bad.validation.pucch_resources.resources(1).starting_prb=120;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue(1,1)), ...
    'sixgr:phy:pucch:InvalidPRBAllocation');
% Ownership export must label the second SYMBOL group as hop 1, not every
% PRB except the first as hop 1. Exercise multi-PRB and equal-frequency hops.
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(mod((0:10).',2)),'NSizeGrid',273,'SCS',carrier.SubcarrierSpacing);
d=f.Assignment.Resource.Data; d.NStartBWP=20; d.NSizeBWP=120; d.NumPRBs=4;
for hopping=[false true]
    d.IntraSlotHopping=hopping; d.SecondHopStartPRB=d.StartPRB;
    resource=sixgr.phy.pucch.PUCCHResource(d);
    a=sixgr.phy.pucch.PUCCHTransmissionAssignment(f.Assignment.Data,resource, ...
        f.Assignment.PowerControlState,f.Assignment.SpatialRelationState);
    ownership=sixgr.phy.pucch.PUCCHResourceOwnershipMap.build(carrier,a);
    expected=zeros(height(ownership.Table),1);
    if hopping, expected=double(ownership.Table.Symbol>=d.StartSymbol+floor(d.NumSymbols/2)); end
    assert(isequal(ownership.Table.Hop,expected));
    assert(all(ownership.Table.PRB>=13+d.StartPRB & ownership.Table.PRB<13+d.StartPRB+d.NumPRBs));
    waveformData=d;
    if hopping, waveformData.SecondHopStartPRB=100; end
    localPhysicalBWPRoundTrip(f,carrier,waveformData);
end
fprintf('SLS_UCI_BINDINGS_PASS cells=21 UEs=210 SR_obligations=210 offset_BWP_waveforms=2 waveform_qualification=0\n');
ok=true;
end

function localPhysicalBWPRoundTrip(f,carrier,d)
% Install both endpoints independently before waveform generation. Receiver
% obtains only the report schema and installed resource, never TX bits.
rrcData=f.RRCContext.Data; rrcData.Resources=d;
for name=["NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"]
    rrcData.CarrierConfiguration.(name)=carrier.(name);
end
rrc=sixgr.phy.pucch.PUCCHRRCContext(rrcData);
ueData=f.UEContext.Data; ueData.RRCContext=rrc;
rx=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',"offset_bwp_component",'ResourceID',d.ID,'RNTI',d.RNTI, ...
    'AbsoluteSlot0',0,'Source',"installed_component_obligation", ...
    'TimingSource',"received_PUCCH_DMRS",'ResourceSelectionProcedure',"configured_csi"),rrc,f.Context);
plan=sixgr.phy.pucch.PUCCHResourcePlan(f.Report,ueData,rrc,f.FrameState,"declared_component_dynamic_harq");
p=f.Assignment.PowerControlState.Data; p.MRB=plan.Resource.Data.NumPRBs;
assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromResourcePlan(plan, ...
    sixgr.phy.pucch.PUCCHPowerControlState(p),f.Assignment.SpatialRelationState);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,assignment,f.Report);
[waveform,~]=sixgr.link.addRuntimeComplexNoise(tx.Waveform,1e-8,814+double(d.IntraSlotHopping),0,struct());
result=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,carrier,rx,f.Context, ...
    'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
    'ChannelProfile','AWGN','DetectionThreshold',0.2);
assert(result.ReceiverOnlyAssignment && ~result.OraclePayloadBitsUsed && ...
    result.ReceiverUsable && ~result.DTX && result.CRCPassed);
assert(isequal(result.DecodedFields.CSIPart1,int8(mod((0:10).',2))));
end

function reject(f,id)
threw=false;
try, f(); catch e, assert(strcmp(e.identifier,id),'%s: %s',e.identifier,e.message); threw=true; end
assert(threw,'Expected rejection %s.',id);
end
