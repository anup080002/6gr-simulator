function ok=testDLReferenceSignaling()
% Independent table vectors, exact DCI bits, YAML and actual scheduled PHY.
setup6GRSimToolkit('Verbose',false);
context=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'1_1');
data=context.Data;
data.DLReferenceSignaling=struct('dmrs_configuration_type',1,'dmrs_max_length',1, ...
    'dmrs_type_enhanced',false,'two_tci_states',false,'max_codewords',1);
% TS 38.212 table 7.3.1.2.2-1: value, CDM groups, logical ports.
rows={0,1,0;1,1,1;2,1,[0 1];3,2,0;4,2,1;5,2,2;6,2,3; ...
    7,2,[0 1];8,2,[2 3];9,2,[0 1 2];10,2,[0 1 2 3];11,2,[0 2]};
context=sixgr.phy.pdcch.DCIContext(data);
for k=1:size(rows,1)
    expected=rows{k,1}; groups=rows{k,2}; ports=rows{k,3}; rank=numel(ports);
    assert(sixgr.phy.pdcch.DLReferenceSignaling.encodeAntenna(data,rank,ports,groups,1)==expected);
    [actualPorts,actualGroups,actualRank]=sixgr.phy.pdcch.DLReferenceSignaling.decodeAntenna(data,expected);
    assert(isequal(actualPorts,ports) && actualGroups==groups && actualRank==rank);
    payload=sixgr.phy.pdcch.buildDCI11DownlinkAssignment(struct('NSizeGrid',25,'DCIContext',context), ...
        'NumLayers',rank,'DMRSPortSet',ports,'NumCDMGroupsWithoutData',groups);
    received=sixgr.phy.pdcch.decodeDCIPayload(payload.Bits,'1_1',context);
    assert(received.Fields.antenna_ports==expected && received.Fields.num_layers==rank && ...
        isequal(received.Fields.dmrs_port_set,ports) && received.Fields.dmrs_num_cdm_groups_without_data==groups);
    ap=payload.FieldTable(string(payload.FieldTable.FieldName)=="antenna_ports",:);
    % FieldTable uses zero-based offsets; check bits independently of packer.
    expectedBits=int8(bitget(uint8(expected),4:-1:1).');
    assert(ap.WidthBits==4 && isequal(payload.Bits(ap.BitStart+1:ap.BitEnd+1),expectedBits));
end
for value=12:15
    localReject(@()sixgr.phy.pdcch.DLReferenceSignaling.decodeAntenna(data,value), ...
        'sixgr:phy:pdcch:ReservedDLDMRSCodepoint');
end
localReject(@()sixgr.phy.pdcch.DLReferenceSignaling.encodeAntenna(data,2,[0 2],1,1), ...
    'sixgr:phy:pdcch:DLDMRSSelectionNotInTable');
localReject(@()sixgr.phy.pdcch.DLReferenceSignaling.encodeAntenna(data,2,[1 0],1,1), ...
    'sixgr:phy:pdcch:DLDMRSSelectionNotInTable');
bad=data; bad.DLReferenceSignaling.two_tci_states=true;
localReject(@()sixgr.phy.pdcch.DLReferenceSignaling.resolve(bad), ...
    'sixgr:phy:pdcch:UnsupportedDLReferenceContext');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
raw=s.toStruct(); cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
bad=raw; bad.reference_signals.pdsch_dmrs_max_length=2;
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),'sixgr:lls6g:config:DLDMRSContextMismatch');
bad=raw; bad.reference_signals=rmfield(bad.reference_signals,'pdsch_dmrs_max_length');
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),'sixgr:lls6g:config:MissingDLDMRSAuthority');

% Explicit scheduled port must win over the wider available port pool.
g=struct('NumLayers',1,'DMRSPortSet',1,'PRBSet',0:5, ...
    'SymbolAllocation',cfg.phy.pdsch.symbolAllocation);
assert(sixgr.phy.pdcch.DLReferenceSignaling.antennaFromGrant(data,cfg,g)==1);
g.DMRSPortSet=[0 1]; g.NumLayers=2;
assert(sixgr.phy.pdcch.DLReferenceSignaling.antennaFromGrant(data,cfg,g)==2);
ulData=struct('ULPrecoding',raw.control.ul_precoding, ...
    'ULReferenceSignaling',raw.control.ul_reference_signaling,'TransformPrecodingEnabled',false);
g.NumLayers=1; g.DMRSPortSet=1; g.SymbolAllocation=cfg.phy.pusch.symbolAllocation;
assert(sixgr.phy.pdcch.ULReferenceSignaling.antennaFromGrant(ulData,cfg,g)==3, ...
    'UL signaling must not substitute pool port zero for scheduled port one.');

% Actual scheduler packing, coded PDSCH transmitter, and received PDCCH bits.
% Unit channel/control known-size fixture, NOT full 12 dB or blind-size qualification.
% Use an actual DL data occasion, not slot zero (occupied by SS/PBCH).
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,31);
grant=sixgr.link.resolveWaveformGrant(cfg,'DL',4,'Slot',31,'SFN',3);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,double(grant.ScheduledAbsoluteSlot)+1);
[tx,~]=sixgr.phy.dl.PDSCH_Tx(cfg,'PHYGrant',grant.PHYGrant, ...
    'SchedulerGrantContext',grant,'CompactOutput',false);
assert(~isempty(tx.Waveform) && any(abs(tx.Waveform(:))>0));
controlCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,tx.Assignment.get('PDCCHAbsoluteSlot')+1);
p=sixgr.link.preparePDCCHTransmission(controlCfg,'Grant',grant, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
[rx,~]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,controlCfg,'Carrier',p.Tx.Carrier, ...
    'PDCCH',p.Tx.PDCCH,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits), ...
    'SampleRate_Hz',p.SampleRateHz);
assert(rx.Ok,'Actual unit-channel PDCCH reception failed.');
decoded=sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
assert(isequal(decoded.Fields.dmrs_port_set,tx.PDSCH.DMRS.DMRSPortSet) && ...
    decoded.Fields.dmrs_num_cdm_groups_without_data==tx.PDSCH.DMRS.NumCDMGroupsWithoutData && ...
    decoded.Fields.dmrs_front_load_symbols==tx.PDSCH.DMRS.DMRSLength && ...
    decoded.Fields.num_layers==tx.PDSCH.NumLayers);
request=tx.Assignment.toStruct(); request.DMRSPortSet=1;
localReject(@()sixgr.pdsch.bindSchedulerPDSCHTransmitContext(request,cfg,grant, ...
    double(grant.ScheduledAbsoluteSlot),grant.PHYGrant), ...
    'sixgr:pdsch:AuthoredSchedulerDCIAllocationMismatch');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
