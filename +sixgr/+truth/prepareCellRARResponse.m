function [state,next,checkpoint]=prepareCellRARResponse(state,cfg,checkpoint)
% One cell/received-occasion/RAPID owns one physical RAR producer.
% UE monitoring windows are armed separately and remain independent of
% whether this callback created, repeated, or missed a gNB detection.
assert(checkpoint.NextStage==2 && checkpoint.ResumePhase=="decoded", ...
    'sixgr:truth:RARResponseBoundary','RAR allocation follows completed Msg1 reception only.');
next=struct('PreparedTransmission',struct());
if ~checkpoint.Result.PreambleDetected, return; end
pool=sixgr.util.structGet(cfg,'random_access.temporary_crnti_pool',[]);
if ~isfield(state,'GNBTemporaryCRNTIAllocator')
    state.GNBTemporaryCRNTIAllocator=sixgr.mac.ra.RARIdentityAllocator(pool);
end
assert(isequal(state.GNBTemporaryCRNTIAllocator.Pool,double(reshape(pool,1,[]))), ...
    'sixgr:truth:RARIdentityPoolChanged','The cell allocation policy cannot change during a physical run.');
cellID=checkpoint.RAConfig.ServingCell;
bindings=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));
used=[];
if ~isempty(bindings), used=[bindings([bindings.ServingCell]==cellID).RNTI]; end
det=checkpoint.Detection;
detections=sixgr.util.structGet(det,'Detections',det);
assert(~isempty(detections),'sixgr:truth:MissingPRACHDetections','Successful detection requires measured candidates.');
[~,order]=sort([detections.DetectedPreambleIndex]); detections=detections(order);
allocator=state.GNBTemporaryCRNTIAllocator;
assignments=cell(numel(detections),1); created=false(numel(detections),1);
for k=1:numel(detections)
    [allocator,assignments{k},created(k)]=allocator.reserve(checkpoint.RAConfig,detections(k),used);
end
if ~any(created)
    checkpoint.Result.GNBResponseOwnedByCell=true;
    return; % Do not add a second coherent copy of the same cell response.
end
assert(all(created),'sixgr:truth:RARDetectionSetChanged', ...
    'A frozen occasion response cannot acquire additional RAPIDs from a later UE callback.');
assignment=assignments{find([detections.DetectedPreambleIndex]==det.DetectedPreambleIndex,1)};
prior=state.GNBTemporaryCRNTIAllocator.Allocations;
if ~isempty(prior)
    sameOccasion=[prior.ServingCell]==assignment.ServingCell & ...
        [prior.PRACHAbsoluteSlot]==assignment.PRACHAbsoluteSlot & ...
        [prior.PRACHOccasionSymbol]==assignment.PRACHOccasionSymbol & ...
        [prior.PRACHFrequencyIndex]==assignment.PRACHFrequencyIndex;
    assert(~any(sameOccasion),'sixgr:truth:RARMultiResponseMultiplexingRequired', ...
        ['Distinct RAPIDs in one received occasion require one explicitly multiplexed RAR/grant plan. ' ...
         'Do not superpose separately prepared RARs on the same allocation.']);
end
responses=cell(numel(detections),1);
ra=checkpoint.RAConfig;
for k=1:numel(detections)
    assigned=ra;
    assigned.Msg3PUSCH.PRBStart=ra.Msg3PUSCH.PRBStart+(k-1)*ra.Msg3PUSCH.NumPRB;
    assert(assigned.Msg3PUSCH.PRBStart+assigned.Msg3PUSCH.NumPRB<=ra.NSizeGrid, ...
        'sixgr:truth:RARMsg3CapacityExceeded', ...
        'Detected RAPIDs exceed the non-overlapping Msg3 capacity; no overlapping grants may be issued.');
    grant=sixgr.mac.ra.buildRARULGrant(assigned);
    ta=sixgr.phy.ra.estimateTimingAdvanceFromPRACH( ...
        detections(k),checkpoint.Msg1Tx.SampleRate_Hz,ra.CarrierSCSkHz);
    assert(ta.Valid,'sixgr:truth:RARMissingMeasuredTiming','RAR requires measured per-preamble timing.');
    responses{k}=sixgr.mac.ra.encodeMACRAR('RAPID',detections(k).DetectedPreambleIndex, ...
        'TimingAdvanceCommand',ta.TimingAdvanceCommand, ...
        'TemporaryCRNTI',assignments{k}.TemporaryCRNTI,'ULGrant',grant);
end
plan=struct('RAR',sixgr.mac.ra.multiplexMACRAR(vertcat(responses{:})), ...
    'Assignments',vertcat(assignments{:}),'Source',"cell_received_preamble_set_disjoint_msg3_grants");
[next,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',checkpoint, ...
    'StageAction','prepare_next_stage','GNBIdentityAssignment',assignment,'GNBResponsePlan',plan);
assert(~isempty(fieldnames(next.PreparedTransmission)) && ...
    next.PreparedTransmission.StageName=="Msg2", ...
    'sixgr:truth:RARAllocationWithoutTransmission','Commit the lease only with its actual prepared RAR.');
state.GNBTemporaryCRNTIAllocator=allocator;
checkpoint.Result.GNBResponseOwnedByCell=true;
end
