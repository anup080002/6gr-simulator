function [state,response]=prepareReceivedCellRARResponse(state,item,receipt)
% Independent completed cell detector -> common RAR preparation/enqueue.
% UE retry/selected preamble/checkpoint state is deliberately not consulted.
owner=state.SharedWaveformStream; owner.validateCellPRACHCompletion(item);
c=item.Context.Calendar; cfg=item.Context.Config;
assert(receipt.ObservationID==item.ID && receipt.CellCalendarSHA256==c.SHA256 && ...
    receipt.CompletedAtSample==owner.Events.NextSampleIndex && ...
    receipt.SHA256==localHash(rmfield(receipt,'SHA256')), ...
    'sixgr:truth:CellRAROriginalReceiverRequired','Use the original completed cell detector receipt.');
response=struct('ReceiverReceiptSHA256',receipt.SHA256,'Status',"no_admitted_detection", ...
    'ComponentID',"",'Prepared',struct(),'DeferredRAPIDs',zeros(0,1));
if isempty(receipt.AdmittedDetections),return;end
carrier=sixgr.phy.grid.makeCarrier(cfg);
all=receipt.AdmittedDetections;
[~,order]=sort([all.DetectedPreambleIndex]);all=all(order);
% One physical response uses one original SSB-associated beam. Other
% detected beam groups remain explicitly unserved in this RO, allowing
% their independent UE response windows/retry procedures to run normally.
group=all([all.AssociatedSSBIndex0]==all(1).AssociatedSSBIndex0);
start=cfg.random_access.msg3_pusch.prb_start;count=cfg.random_access.msg3_pusch.num_prb;
validateattributes(start,{'numeric'},{'scalar','real','integer','nonnegative','finite'});
validateattributes(count,{'numeric'},{'scalar','real','integer','positive','finite'});
capacity=floor((carrier.NSizeGrid-start)/count);
assert(capacity>=1,'sixgr:truth:CellRARMsg3Capacity','No valid configured Msg3 allocation fits the initial BWP.');
selected=group(1:min(capacity,numel(group)));
selectedRAPIDs=[selected.DetectedPreambleIndex];
response.DeferredRAPIDs=reshape([all(~ismember([all.DetectedPreambleIndex],selectedRAPIDs)).DetectedPreambleIndex],[],1);
available=@(dl,ul)isempty(owner.commonRAResources(c.CellID,dl,"DL",carrier)) && ...
    isempty(owner.commonRAResources(c.CellID,ul,"UL",carrier));
[txcfg,ra,policy]=sixgr.truth.buildCellRARTransmissionContext(cfg,c,receipt,available,selectedRAPIDs);
if ~ra.ResponseSchedulable
    response.Status="no_causal_disjoint_RAR_and_Msg3_opportunity_in_response_window";return;
end
allocation=sixgr.phy.ra.generateMsg2RARWaveform(txcfg,ra,struct(),'AllocationOnly',true);
% This producer emits only RAPID subPDUs (one header octet + seven RAR
% octets each), with no BI subheader. Bound admission by the real scheduled
% DL-SCH TBS as well as the disjoint Msg3 allocation capacity.
tbCapacity=floor(allocation.TransportBlockSize/64);
assert(tbCapacity>=1,'sixgr:truth:CellRARTBTooSmall','The configured actual RAR allocation cannot carry one MAC RAR.');
if numel(selected)>tbCapacity
    selected=selected(1:tbCapacity);selectedRAPIDs=[selected.DetectedPreambleIndex];
    response.DeferredRAPIDs=reshape([all(~ismember([all.DetectedPreambleIndex],selectedRAPIDs)).DetectedPreambleIndex],[],1);
    [txcfg,ra,policy]=sixgr.truth.buildCellRARTransmissionContext(cfg,c,receipt,available,selectedRAPIDs);
end
pool=cfg.random_access.temporary_crnti_pool;
if ~isfield(state,'GNBTemporaryCRNTIAllocator')
    state.GNBTemporaryCRNTIAllocator=sixgr.mac.ra.RARIdentityAllocator(pool);
end
assert(isequal(state.GNBTemporaryCRNTIAllocator.Pool,double(reshape(pool,1,[]))), ...
    'sixgr:truth:RARIdentityPoolChanged','The original allocation policy cannot change.');
bindings=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));used=[];
if ~isempty(bindings),used=[bindings([bindings.ServingCell]==c.CellID).RNTI];end
context=struct();
for name=["ServingCell","CellId","PRACHAbsoluteSlot","PRACHOccasionSymbol","PRACHFrequencyIndex","RARNTI"]
    context.(name)=ra.(name);
end
% A RAR may respond to a subset when its disjoint Msg3 capacity is finite.
% Deterministic ascending RAPID is cell admission policy, not a PHY result.
[plan,allocator]=sixgr.mac.ra.buildCellRARResponsePlan(context,policy,selected, ...
    receipt.Plan.SampleRateHz,state.GNBTemporaryCRNTIAllocator,used);
if ~plan.ResponseRequired,response.Status=plan.Status;return;end
plan.OriginalReceiverReceiptSHA256=receipt.SHA256;
plan.OriginalReceiverObservationID=receipt.ObservationID;
assert(plan.RAR.BitLength<=allocation.TransportBlockSize, ...
    'sixgr:truth:CellRARTBCapacityChanged','Original multiplexed MAC bytes must fit the exact scheduled DL-SCH TBS.');
plan.CellAdmissionPolicy="lowest_RAPID_associated_beam_then_ascending_RAPID_DL_TBS_and_disjoint_Msg3_capacity";
plan.ScheduledRARTransportBlockSize=allocation.TransportBlockSize;
plan.DeferredRAPIDs=response.DeferredRAPIDs;
plan.PlanSHA256=localHash(rmfield(plan,'PlanSHA256'));
prepared=sixgr.truth.prepareCellRARTransmission(txcfg,ra,plan);
[id,~]=owner.queueCellRARTransmission(prepared);
% Identity leases commit only after the original samples were accepted.
state.GNBTemporaryCRNTIAllocator=allocator;
response.Status="original_cell_RAR_enqueued_not_yet_transmitted";
response.ComponentID=id;response.Prepared=prepared;
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
