function emissions=buildScheduledSRSEmissions(cfg,state)
% Native SRS symbols for actual periodic occasions in connected ideal SLS.
% A resource reservation is not an emitter. This function executes native
% symbol generation, binds UE/cell/slot and power, and retains its digest.
% Propagation/feedback remain explicitly modeled, not waveform reception.
emissions=struct([]);
p=cfg.system.linkAbstraction.networkSpatial;
assert(string(p.srsPowerPolicy)=="configured_ue_total_power_per_srs_symbol" && ...
    string(p.srsPhaseAssumption)=="native_sequence_phase_at_committed_epoch", ...
    'sixgr:abstraction:SRSEmissionPolicy','Declare SRS power and relative-phase assumptions.');
assert(isfield(state,'AbsoluteSlot0') && state.AbsoluteSlot0==state.TTI-1 && ...
    all(isfield(state,{'ServingCells','RNTIByUE'})) && ...
    numel(state.ServingCells)==numel(state.RNTIByUE), ...
    'sixgr:abstraction:SRSEmissionIdentity','Committed connected UEs require explicit slot, cell and RNTI identities.');
if ~logical(sixgr.util.structGet(cfg,'phy.srs.enable',false)), return; end
for u=1:numel(state.ServingCells)
cellID=state.ServingCells(u); rnti=state.RNTIByUE(u);
[userCfg,resourceBinding]=sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,u,rnti,cellID);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(userCfg);
sri=sixgr.system.abstraction.singleSRSResourceIndicator(strict);
srs=strict.ToolboxSRS; slot=state.AbsoluteSlot0;
assert(isnumeric(srs.SRSPeriod) && numel(srs.SRSPeriod)==2 && ...
    srs.NumSRSPorts==p.uePorts, ...
    'sixgr:abstraction:SRSEmissionConfig','Require periodic SRS with the configured UE port basis.');
if mod(slot-srs.SRSPeriod(2),srs.SRSPeriod(1))~=0, continue; end
slots=sixgr.util.structGet(cfg,'phy.srs.slotNumbers',[]);
if ~isempty(slots) && ~ismember(slot,slots), continue; end
carrier=nrCarrierConfig('NSizeGrid',cfg.phy.carrier.NSizeGrid, ...
    'NStartGrid',cfg.phy.carrier.NStartGrid,'SubcarrierSpacing',cfg.phy.carrier.SubcarrierSpacing, ...
    'NCellID',cfg.phy.carrier.NCellID);
carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
carrier.NFrame=mod(floor(slot/carrier.SlotsPerFrame),1024);
indices=nrSRSIndices(carrier,srs); values=nrSRS(carrier,srs);
assert(~isempty(indices) && ~isempty(values),'sixgr:abstraction:SRSEmissionConfig', ...
    'A due configured SRS occasion did not produce native symbols.');
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot; ports=srs.NumSRSPorts;
grid=nrResourceGrid(carrier,ports); grid(indices)=values;
flat=reshape(grid,K*L,ports); occupied=find(any(flat~=0,2));
[k,l]=ind2sub([K L],occupied); coords=[k-1 l-1]; symbols=double(flat(occupied,:));
part=sixgr.util.resolveTDDSlotPartition(cfg,slot); a=part.ULSymbolAllocation;
assert(all(coords(:,2)>=a(1) & coords(:,2)<sum(a)), ...
    'sixgr:abstraction:SRSEmissionTiming','Transmitted SRS must fit actual UL symbols.');
W=eye(ports)/sqrt(ports);
nativeConfiguration=struct(); metadata=metaclass(srs);
for k=1:numel(metadata.PropertyList)
    property=metadata.PropertyList(k);
    if ~property.Constant && ischar(property.SetAccess) && strcmp(property.SetAccess,'public')
        nativeConfiguration.(property.Name)=srs.(property.Name);
    end
end
    validateattributes([cellID rnti],{'numeric'},{'integer','positive','finite','numel',2});
    tx=cfg.scenario.ue.txPower_dBm; if ~isscalar(tx), tx=tx(u); end
    validateattributes(tx,{'numeric'},{'scalar','real','finite'});
    watts=10^((tx-30)/10); power=zeros(size(coords,1),1);
    % Keep native comb/CDM amplitudes, including any port-specific zero REs.
    % Total antenna-grid energy in each occupied OFDM symbol is the declared
    % UE power. Do not incorrectly divide by the whole carrier or port count twice.
    antennaSymbols=symbols*W.';
    for symbol=reshape(unique(coords(:,2)),1,[])
        active=coords(:,2)==symbol;
        energy=sum(abs(antennaSymbols(active,:)).^2,'all');
        assert(energy>0,'sixgr:abstraction:SRSEmissionPower','Silent native SRS symbol.');
        power(active)=watts/energy;
    end
    % A UE cannot execute overlapping PUSCH and SRS with this simultaneous
    % emission model. Other-cell/user collisions remain real interference.
    for j=1:numel(state.GrantsUL)
        g=state.GrantsUL(j);
        if sixgr.system.resolveGrantUEIndex(g)~=u, continue; end
        assert(~any(coords(:,2)>=g.SymbolAllocation(1) & coords(:,2)<sum(g.SymbolAllocation)), ...
            'sixgr:abstraction:SRSEmissionPUSCHCollision', ...
            'Same-UE PUSCH/SRS symbol overlap needs an explicit multiplexing and shared-power procedure.');
    end
    row=struct('SourceTTI',state.TTI,'AbsoluteSlot0',slot,'UEIndex',u, ...
        'ServingCellID',cellID,'RNTI',rnti,'ResourceID',double(strict.ResourceId),'SRI',sri, ...
        'Signal',"SRS",'Coordinates0Based',coords,'Symbols',symbols, ...
        'Precoder',W,'TransmitPowerPerRE_W',power,'ConfiguredTotalPower_W',watts, ...
        'SymbolSource',"nrSRS_and_nrSRSIndices",'PhaseAssumption',string(p.srsPhaseAssumption), ...
        'PowerPolicy',string(p.srsPowerPolicy),'NativeSRSConfiguration',nativeConfiguration, ...
        'UEFrequencyResourceBinding',resourceBinding);
    row.SHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(row)),'UTF-8'))));
    emissions=[emissions row]; %#ok<AGROW>
end
end
