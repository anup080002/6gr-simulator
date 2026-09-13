function ok=testConnectedTRSResourceSharing()
% Dedicated/common ownership and actual control-waveform receive allocation.
% This isolated noiseless control fixture is NOT shared-stream qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,9); % Zero-based special slot 8.
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
allocation=struct('PRBStart',3,'NumPRB',6,'SymbolStart',2,'NumSymbols',8);
before=rng;
[free,common]=plan.checkPDSCH(allocation,8);
assert(~free && any(common.ConflictingOwners=="TRS"));
[free,connected]=plan.checkConnectedPDSCH(allocation,8);
assert(free && connected.TRSRateMatchedRECount>0 && ...
    ~connected.ProxyUsed && ~connected.FallbackUsed && isequal(before,rng));
assert(~plan.checkPDSCH(allocation,8),'Connected eligibility must not mutate common/RA ownership.');
[~,inactive]=plan.checkConnectedPDSCH(allocation,3);
assert(inactive.TRSRateMatchedRECount==0,'No inherited TRS reservation on an inactive slot.');

% SIB1 remains protected through the connected entry point as well.
ra=sixgr.mac.ra.RAConfig(cfg);
[free,si]=plan.checkConnectedPDSCH(ra.Msg4PDSCH,plan.SIB1Slot0);
assert(~free && any(si.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));

% Pack and transmit control, then independently construct UE allocation
% from decoded DCI plus its installed reference policy (no TX reservation).
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,"1_1");
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); f=struct();
for def=schema.Definitions(:).', f.(def.Name)=def.ValueMin; end
f.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*5+3;
f.time_resource_assignment=1; f.mcs=10; f.ndi=1; f.antenna_ports=4;
dci=sixgr.phy.pdcch.DCIPacker.pack(f,context);
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',dci.Bits,'RNTI',cfg.phy.pdsch.RNTI);
[control,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,cfg,'SampleRate_Hz',p.SampleRateHz);
a=sixgr.phy.pdcch.materializeConnectedDCI(control,info,cfg);
assert(a.DataAbsoluteSlot==8 && isequal(a.SymbolAllocation,[2 8]));
rx=sixgr.phy.pdcch.connectedDataAllocation(cfg,a);
assert(~rx.ExecutionQualified && rx.Source=="received_dci_and_installed_reference_policy");
disabled=cfg; disabled.phy.trs.enable=false;
without=sixgr.phy.pdcch.connectedDataAllocation(disabled,a);
assert(rx.RateMatchedCapacityBits<without.RateMatchedCapacityBits);
assert(numel(setdiff(without.Indices,rx.Indices))==connected.TRSRateMatchedRECount);
assert(all(ismember(setdiff(double(without.Indices(:))-1,double(rx.Indices(:))-1), ...
    double(rx.ChannelConfig.ReservedRE(:)))));
fprintf('CONNECTED_TRS_SHARING_PASS slot0=8 reserved_RE=%d G=%d G_without_TRS=%d received_DCI=1 shared_stream_qualified=0\n', ...
    connected.TRSRateMatchedRECount,rx.RateMatchedCapacityBits,without.RateMatchedCapacityBits);
ok=true;
end
