function out=resolveSLSResourceReservations(cfg,tti,direction,budget,context)
%RESOLVESLSRESOURCERESERVATIONS Causal resource ownership before scheduling.
% Coordinates are configured/scheduled ownership, never proof of RF execution.
% A single rectangular grant budget cannot use different PRBs per symbol:
% retain only PRBs free for that entire budget and disclose that restriction.
% DMRS/PTRS inside a data grant remain part of its gross PRB-symbol footprint.
arguments
    cfg struct
    tti (1,1) double {mustBeInteger,mustBePositive}
    direction (1,1) string {mustBeMember(direction,["DL","UL"])}
    budget struct
    context struct
end
required={'CellID','AsOfAbsoluteSlot0','PUCCHObligationsComplete'};
assert(all(isfield(context,required)),'sixgr:system:ReservationContext', ...
    'Provide CellID, AsOfAbsoluteSlot0 and explicit PUCCHObligationsComplete.');
cellID=double(context.CellID); asof=double(context.AsOfAbsoluteSlot0); slot0=tti-1;
validateattributes(cellID,{'numeric'},{'scalar','integer','positive'});
validateattributes(asof,{'numeric'},{'scalar','integer','nonnegative','<=',slot0});
carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
carrier.NFrame=mod(floor(slot0/carrier.SlotsPerFrame),1024);
nrb=double(carrier.NSizeGrid); nsym=double(carrier.SymbolsPerSlot);
allowed=[0 nsym];
if sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD"
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot0);
    if direction=="DL", allowed=double(partition.DLSymbolAllocation);
    else, allowed=double(partition.ULSymbolAllocation); end
end
if isfield(budget,'PRBSet')
    prbs=double(budget.PRBSet(:).');
else
    validateattributes(budget.NPRB,{'numeric'},{'scalar','integer','nonnegative','<=',nrb});
    prbs=0:double(budget.NPRB)-1;
end
sym=double(budget.SymbolAllocation(:).');
if ~isempty(prbs), validateattributes(prbs,{'numeric'},{'vector','integer','nonnegative','<',nrb}); end
assert(numel(unique(prbs))==numel(prbs) && numel(sym)==2 && ...
    all(isfinite(sym)) && all(sym==fix(sym)) && all(sym>=0) && sum(sym)<=nsym, ...
    'sixgr:system:ReservationBudget','Exact legal zero-based PRBs and [start,count] symbols required.');
assert(sym(2)==0 || (sym(1)>=allowed(1) && sum(sym)<=sum(allowed)), ...
    'sixgr:system:ReservationTDDCollision','Data budget crosses guard/opposite-direction symbols.');
available=false(nrb,nsym); available(prbs+1,sym(1)+(1:sym(2)))=true;
initial=available; reserved=false(nrb,nsym);
rows=repmat(localRow(),0,1);
prior=sixgr.util.structGet(budget,'ReservedResourceRegions',struct([]));
for k=1:numel(prior)
    if isfield(prior(k),'CellID') && double(prior(k).CellID)~=cellID, continue; end
    assert(all(isfield(prior(k),{'PRBSet','SymbolAllocation'})), ...
        'sixgr:system:ReservationBudget','Existing reservation lacks exact PRB/symbol allocation.');
    a=double(prior(k).SymbolAllocation); p=double(prior(k).PRBSet);
    assert(numel(a)==2 && all(a>=0) && all(a==fix(a)), ...
        'sixgr:system:ReservationBudget','Invalid existing reservation symbols.');
    [sc,sy]=ndgrid(reshape(p(:)*12+(0:11),[],1),a(1)+(0:a(2)-1));
    add("budget_region_"+string(k),"CONFIGURED_REGION",[sc(:),sy(:),zeros(numel(sc),1)], ...
        "configured_whole_PRB_symbol_region","existing_scheduler_budget",0,0);
end
% Configured CORESET ownership is a monitoring envelope; no DCI is invented.
if direction=="DL" && allowed(2)>0 && logical(sixgr.util.structGet(cfg,'phy.pdcch.enable',false))
    p=sixgr.util.structGet(context,'PDCCHConfiguration',[]);
    if isempty(p)
        if isfield(sixgr.util.structGet(cfg,'phy.pdcch.operatorControl',struct()),'connected_dci')
            p=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,double(cfg.phy.pdsch.RNTI),false);
        else
            strict=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(cfg); p=strict.ToolboxPDCCH;
        end
    end
    period=double(p.SearchSpace.SlotPeriodAndOffset);
    if mod(slot0-period(2),period(1))<double(p.SearchSpace.Duration)
        m=sixgr.phy.frame.ChannelAllocationMaterializer.materializePDCCH(carrier,p,'AbsoluteSlot',slot0);
        coordinates=m.CORESETAllocation.RECoordinates;
        add("CORESET_"+string(p.CORESET.CORESETID),"PDCCH",coordinates, ...
            "configured_monitoring_envelope","installed_CORESET_SearchSpace",0,0);
    end
end
if direction=="UL" && allowed(2)>0 && logical(sixgr.util.structGet(cfg,'phy.srs.enable',false))
    s=sixgr.util.structGet(context,'SRSConfiguration',[]);
    if isempty(s)
        strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg); s=strict.ToolboxSRS;
    end
    if isnumeric(s.SRSPeriod) && numel(s.SRSPeriod)==2
        due=mod(slot0-double(s.SRSPeriod(2)),double(s.SRSPeriod(1)))==0;
    else
        assert(isfield(context,'SRSObligationsComplete') && ...
            islogical(context.SRSObligationsComplete) && context.SRSObligationsComplete, ...
            'sixgr:system:SRSReservationAuthority', ...
            'Nonperiodic SRS requires an explicitly complete independently scheduled obligation ledger.');
        due=false;
    end
    configuredSlots=sixgr.util.structGet(cfg,'phy.srs.slotNumbers',[]);
    if ~isempty(configuredSlots), due=due && ismember(slot0,double(configuredSlots)); end
    if due
        m=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal(carrier,'SRS',s,'AbsoluteSlot',slot0);
        add("SRS_configured_resource","SRS",m.ActualCoordinates0Based, ...
            "configured_periodic_resource","installed_SRS_calendar_nrSRSIndices",0,0);
    end
end
obligations=sixgr.util.structGet(context,'Obligations',struct([]));
common=sixgr.util.structGet(context,'CommonChannelAllocations',table());
for k=1:height(common)
    if string(common.direction(k))~=direction, continue; end
    slots=str2double(split(string(common.occurrence_slots(k)),"|"));
    assert(all(isfinite(slots)) && all(slots>=0 & slots==fix(slots)), ...
        'sixgr:system:CommonReservationCalendar','Retain exact zero-based occurrence slots.');
    if ~ismember(slot0,slots), continue; end
    sc=double(common.subcarrier_start(k))+(0:double(common.subcarrier_count(k))-1);
    coordinates=[sc(:),repmat(double(common.symbol_index(k)),numel(sc),1), ...
        repmat(double(common.port_index(k)),numel(sc),1)];
    add(string(common.allocation_id(k))+":"+string(common.component(k)), ...
        string(common.channel(k)),coordinates,"configured_common_channel_calendar", ...
        string(common.resolver(k)),0,0);
end
if direction=="UL" && allowed(2)>0 && logical(sixgr.util.structGet(cfg,'phy.pucch.enable',false))
    assert(islogical(context.PUCCHObligationsComplete) && context.PUCCHObligationsComplete, ...
        'sixgr:system:MissingPUCCHReservationAuthority', ...
        'Enabled PUCCH requires a complete causal receive-obligation ledger, including empty occasions.');
end
fields={'ResourceID','CellID','UEIndex','Direction','AbsoluteSlot0', ...
    'KnownAtAbsoluteSlot0','Channel','Coordinates0Based','EvidenceKind','Source'};
for k=1:numel(obligations)
    o=obligations(k);
    assert(all(isfield(o,fields)),'sixgr:system:ReservationObligationSchema', ...
        'Each obligation requires identity, exact coordinates, causal clock and evidence source.');
    if double(o.CellID)~=cellID || double(o.AbsoluteSlot0)~=slot0 || string(o.Direction)~=direction
        continue;
    end
    assert(double(o.KnownAtAbsoluteSlot0)<=asof && double(o.KnownAtAbsoluteSlot0)>=0, ...
        'sixgr:system:NoncausalReservation','Resource obligations cannot use future state.');
    assert(any(string(o.EvidenceKind)==["scheduled_receive_obligation","observed_transmitted_resource"]), ...
        'sixgr:system:ReservationEvidenceKind','Declare scheduled obligation or observed transmission.');
    if string(o.Channel)=="PUCCH"
        assert(isfield(o,'Transport') && any(string(o.Transport)==["PUCCH","PUSCH"]), ...
            'sixgr:system:PUCCHTransportAuthority','PUCCH obligation requires selected UCI transport.');
        % Unioning independently sourced obligation schemas leaves absent
        % optional values empty. Empty is not a positive CSI-only claim.
        if isfield(o,'CSIOnly') && ~isempty(o.CSIOnly) && logical(o.CSIOnly)
            assert(isfield(o,'ReferenceAvailableAtSlot0') && ...
                isfinite(double(o.ReferenceAvailableAtSlot0)) && double(o.ReferenceAvailableAtSlot0)<=asof, ...
                'sixgr:system:NoncausalCSIReservation','CSI-only PUCCH requires causal reference availability.');
        end
        if string(o.Transport)=="PUSCH"
            sixgr.system.validateSLSPUSCHUCIReservation(o,context);
            continue;
        end
    end
    add(string(o.ResourceID),string(o.Channel),o.Coordinates0Based, ...
        string(o.EvidenceKind),string(o.Source),double(o.KnownAtAbsoluteSlot0),double(o.UEIndex));
end
available=initial & ~reserved;
symbols=sym(1)+(1:sym(2));
safe=prbs;
if ~isempty(symbols), safe=prbs(all(available(prbs+1,symbols),2)); end
budgetOut=budget; budgetOut.PRBSet=safe; budgetOut.NPRB=numel(safe);
budgetOut.CellID=cellID;
% Empty PRBSet alone triggers legacy defaultBudget fallback; NPRB=0 also
% prevents reinvention of the full bandwidth for a fully reserved slot.
budgetOut.ResourceReservationApplied=true;
budgetOut.ResourceReservationPolicy="whole_PRB_exclusion_over_fixed_grant_symbol_span";
budgetOut.ReservedResourceRegions=struct([]); % already applied to exact PRBSet
out=struct('Budget',budgetOut,'Evidence',struct2table(rows), ...
    'InitialPRBSymbolMask',initial,'ExactAvailablePRBSymbolMask',available, ...
    'SchedulerAvailablePRBSymbolMask',false(nrb,nsym), ...
    'ReservedPRBSymbolMask',reserved,'ReservationSource',"causal_configured_or_scheduled_resource_ownership", ...
    'AsOfAbsoluteSlot0',asof,'DataAbsoluteSlot0',slot0,'CellID',cellID, ...
    'InitialOpportunityCount',nnz(initial),'ExactOpportunityCount',nnz(available), ...
    'SchedulerOpportunityCount',numel(safe)*sym(2), ...
    'OpportunityConservatismCount',nnz(available)-numel(safe)*sym(2));
out.SchedulerAvailablePRBSymbolMask(safe+1,symbols)=true;

    function add(id,channel,coordinates,kind,source,known,ue)
        coordinates=double(coordinates);
        assert(size(coordinates,2)==3 && all(isfinite(coordinates),'all') && ...
            all(coordinates>=0,'all') && all(coordinates==fix(coordinates),'all') && ...
            all(coordinates(:,1)<12*nrb) && all(coordinates(:,2)<nsym), ...
            'sixgr:system:ReservationCoordinates','Require exact carrier-relative [subcarrier,symbol,port] coordinates.');
        if isempty(coordinates), return; end
        assert(all(coordinates(:,2)>=allowed(1) & coordinates(:,2)<sum(allowed)), ...
            'sixgr:system:ReservationTDDCollision','Configured reservation crosses guard/opposite-direction symbols.');
        pairs=unique([floor(coordinates(:,1)/12),coordinates(:,2)],'rows');
        for z=1:size(pairs,1), reserved(pairs(z,1)+1,pairs(z,2)+1)=true; end
        r=localRow(); r.TTI=tti; r.AbsoluteSlot0=slot0; r.CellID=cellID; r.UEIndex=ue;
        r.Direction=direction; r.ResourceID=id; r.Channel=channel; r.KnownAtAbsoluteSlot0=known;
        r.PRBSymbolPairsJSON=string(jsonencode(pairs)); r.Coordinates0BasedJSON=string(jsonencode(coordinates));
        r.RECountWithoutPortDuplication=size(unique(coordinates(:,1:2),'rows'),1);
        r.PRBSymbolCount=size(pairs,1); r.EvidenceKind=kind; r.Source=source;
        r.PhysicalTransmissionProven=kind=="observed_transmitted_resource";
        rows(end+1,1)=r;
    end
end
function r=localRow()
r=struct('TTI',NaN,'AbsoluteSlot0',NaN,'CellID',NaN,'UEIndex',NaN, ...
    'Direction',"",'ResourceID',"",'Channel',"",'KnownAtAbsoluteSlot0',NaN, ...
    'PRBSymbolPairsJSON',"",'Coordinates0BasedJSON',"", ...
    'RECountWithoutPortDuplication',0,'PRBSymbolCount',0,'EvidenceKind',"", ...
    'Source',"",'PhysicalTransmissionProven',false);
end
