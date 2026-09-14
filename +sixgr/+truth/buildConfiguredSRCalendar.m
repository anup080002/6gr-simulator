function calendar=buildConfiguredSRCalendar(cfg,ue,firstSlot,lastSlot)
% Payload-free SR resource calendar. No UE MAC pending/prohibit state enters.
% Whole-slot SR occasions; symbol-period scheduling requires its own path.
arguments
    cfg (1,1) struct
    ue (1,1) struct
    firstSlot (1,1) double
    lastSlot (1,1) double
end
catalog=sixgr.util.structGet(cfg,'phy.pucch.srPeriodCatalog',struct());
assert(isstruct(catalog) && isscalar(catalog) && all(isfield(catalog, ...
    {'schema_version','periods_by_scs','max_sr_resources_per_bwp','max_scheduling_request_id'})) && ...
    isequal(catalog.schema_version,1),'sixgr:truth:MissingSRPeriodCatalog', ...
    'Use the SR period catalog installed in the resolved runtime config.');
names=["UEID","RNTI","ServingCell","PUCCHCell","ComponentCarrier","ActiveULBWP"];
assert(all(isfield(ue,names)) && isempty(setdiff(string(fieldnames(ue)),names)), ...
    'sixgr:truth:InvalidSRReceiverIdentity','Only configured receiver identity is accepted.');
for name=names, integer(ue.(name),0,flintmax,'sixgr:truth:InvalidSRReceiverIdentity'); end
assert(ue.UEID>0 && ue.RNTI>0 && ue.RNTI<=65535 && ue.ServingCell>0 && ue.PUCCHCell>0, ...
    'sixgr:truth:InvalidSRReceiverIdentity','UE/cell/RNTI identity is invalid.');
integer(firstSlot,1,flintmax,'sixgr:truth:InvalidSRCalendarRange');
integer(lastSlot,firstSlot,flintmax,'sixgr:truth:InvalidSRCalendarRange');
id=cfg.phy.frame.DefaultIdentity;
assert(ue.PUCCHCell==ue.ServingCell,'sixgr:truth:SRCalendarCellMismatch', ...
    'SR resource configuration belongs to the same serving cell and UL BWP as its PUCCH resource.');
assert(ue.ComponentCarrier==id.ScheduledCCID && ue.ActiveULBWP==id.ULBWPID, ...
    'sixgr:truth:SRCalendarBWPMismatch','Resolve the configured reporting UL BWP first.');
cc=cfg.phy.frame.ComponentCarriers;
cc=cc([cc.CCID]==ue.ComponentCarrier);
assert(isscalar(cc),'sixgr:truth:SRCalendarBWPMismatch','Exactly one carrier must own the SR calendar.');
bwp=cc.BWPs;
bwp=bwp([bwp.BWPID]==ue.ActiveULBWP & upper(string({bwp.Direction}))=="UL");
assert(isscalar(bwp) && bwp.SCSKHz==cfg.phy.carrier.SubcarrierSpacing, ...
    'sixgr:truth:SRCalendarBWPMismatch','Do not reuse another numerology slot calendar.');
policy=catalog.periods_by_scs;
policy=policy([policy.scs_khz]==bwp.SCSKHz);
assert(isscalar(policy),'sixgr:truth:UnsupportedSRNumerology','No installed whole-slot SR period catalog for this SCS.');
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
inventory=double(rrc.Data.SRResources(:));
configs=sixgr.util.structGet(cfg,'validation.pucch_resources.scheduling_request_resources',struct([]));
row=struct('ObligationID',"",'UEIndex',ue.UEID,'RNTI',ue.RNTI, ...
    'ServingCell',ue.ServingCell,'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP, ...
    'PUCCHConfigurationEpoch',rrc.ConfigurationEpoch,'SRResourceConfigurationID',NaN, ...
    'SchedulingRequestID',NaN,'PUCCHResourceID',NaN,'Slot',NaN,'PeriodSlots',NaN, ...
    'OffsetSlots',NaN,'PriorityIndex',NaN,'StartSymbol',NaN,'NumSymbols',NaN, ...
    'ULResourceAvailable',false,'ResourceBlocker',"", ...
    'EvidenceClass',"configured_SR_opportunity_not_transmission_or_reception");
rows=repmat(row,0,1);
if isempty(inventory)
    assert(isempty(configs),'sixgr:truth:UninstalledSRResource','An SR calendar cannot refer to absent installed resources.');
    calendar=struct2table(rows,'AsArray',true); return;
end
assert(isstruct(configs) && ~isempty(configs), ...
    'sixgr:truth:MissingInstalledSRCalendar','SR resource IDs do not specify SR identity, period, offset or priority.');
required=["scheduling_request_resource_id","scheduling_request_id","resource_id", ...
    "periodicity_slots","offset_slots","priority_index","additional_periodicity_capability"];
assert(all(isfield(configs,required)) && isempty(setdiff(string(fieldnames(configs)),required)), ...
    'sixgr:truth:InvalidInstalledSRCalendar','SR calendar accepts only explicit configured fields, never a pending-positive bit.');
assert(numel(configs)<=catalog.max_sr_resources_per_bwp, ...
    'sixgr:truth:InvalidInstalledSRCalendar','Too many installed SR resource configurations in one BWP.');
for c=reshape(configs,1,[])
    integer(c.scheduling_request_resource_id,1,catalog.max_sr_resources_per_bwp,'sixgr:truth:InvalidInstalledSRCalendar');
    integer(c.scheduling_request_id,0,catalog.max_scheduling_request_id,'sixgr:truth:InvalidInstalledSRCalendar');
    integer(c.resource_id,0,flintmax,'sixgr:truth:InvalidInstalledSRCalendar');
    integer(c.periodicity_slots,1,flintmax,'sixgr:truth:InvalidInstalledSRCalendar');
    integer(c.offset_slots,0,c.periodicity_slots-1,'sixgr:truth:InvalidInstalledSRCalendar');
    integer(c.priority_index,0,1,'sixgr:truth:InvalidInstalledSRCalendar');
    capability=c.additional_periodicity_capability;
    assert((islogical(capability)||isnumeric(capability)) && isscalar(capability) && isreal(capability) && ...
        any(capability==[0 1]),'sixgr:truth:InvalidInstalledSRCalendar','Capability must be explicit binary configuration.');
    assert(ismember(c.periodicity_slots,policy.allowed_slot_periods), ...
        'sixgr:truth:UnsupportedSRPeriod','Whole-slot SR period is not supported for this UL SCS.');
    extra=policy.additional_capability_slot_periods;
    assert(isempty(extra) || ~ismember(c.periodicity_slots,extra) || capability, ...
        'sixgr:truth:MissingSRPeriodCapability','This additional SR period requires declared UE capability.');
end
assert(numel(unique([configs.scheduling_request_resource_id]))==numel(configs), ...
    'sixgr:truth:DuplicateSRResourceConfiguration','SR resource-configuration identities must be unique.');
assert(isequal(sort(unique([configs.resource_id].')),sort(unique(inventory))), ...
    'sixgr:truth:UninstalledSRResource','Resolve all listed SR resources explicitly; do not drop unmatched inventory.');
[~,order]=sort([configs.scheduling_request_resource_id]); configs=configs(order);
slots=(firstSlot:lastSlot).';
for c=reshape(configs,1,[])
    resource=rrc.resourceByID(c.resource_id);
    assert(ismember(resource.Format,[0 1]),'sixgr:truth:InvalidSRResourceFormat', ...
        'Standalone SR resources use PUCCH Format 0 or 1.');
    identity=struct('UE',ue,'Configuration',c,'RRCContextDigest',rrc.Digest, ...
        'SubcarrierSpacing_kHz',bwp.SCSKHz,'CyclicPrefix',string(bwp.CyclicPrefix));
    prefix="sr_"+sixgr.phy.pucch.PUCCHUtil.hash(identity);
    occasions=slots(mod(slots-1-c.offset_slots,c.periodicity_slots)==0);
    for slot=reshape(occasions,1,[])
        next=row;
        next.ObligationID=prefix+"_slot_"+slot;
        next.SRResourceConfigurationID=c.scheduling_request_resource_id;
        next.SchedulingRequestID=c.scheduling_request_id; next.PUCCHResourceID=c.resource_id;
        next.Slot=slot; next.PeriodSlots=c.periodicity_slots; next.OffsetSlots=c.offset_slots;
        next.PriorityIndex=c.priority_index;
        next.StartSymbol=resource.Data.StartSymbol; next.NumSymbols=resource.Data.NumSymbols;
        [~,ulAllowed,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
        ul=partition.ULSymbolAllocation;
        next.ULResourceAvailable=ulAllowed && next.StartSymbol>=ul(1) && ...
            next.StartSymbol+next.NumSymbols<=sum(ul);
        if ~next.ULResourceAvailable, next.ResourceBlocker="configured_SR_symbols_not_UL_on_nominal_slot"; end
        rows(end+1,1)=next; %#ok<AGROW>
    end
end
calendar=struct2table(rows,'AsArray',true);
if ~isempty(calendar), calendar=sortrows(calendar,{'Slot','SRResourceConfigurationID'}); end
end
function integer(value,minimum,maximum,id)
assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
    value==fix(value) && value>=minimum && value<=maximum,id,'Invalid configured integer or slot.');
end
