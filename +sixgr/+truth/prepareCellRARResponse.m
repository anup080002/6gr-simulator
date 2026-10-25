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
[receiverFS,receiverRow]=localReceivedClock(checkpoint);
ra=checkpoint.RAConfig;
localAssertAlignedInitialULBWP(cfg,ra);
cellContext=localProject(ra,["ServingCell","CellId","PRACHAbsoluteSlot", ...
    "PRACHOccasionSymbol","PRACHFrequencyIndex","RARNTI"]);
policy=localProject(ra,["NSizeGrid","CarrierSCSkHz","CarrierCyclicPrefix"]);
policy.RARGrantConfig=localProject(ra.RARGrantConfig, ...
    ["field_layout","frequency_hopping","time_resource_assignment","tpc_command"]);
policy.Msg3PUSCH=localProject(ra.Msg3PUSCH,["PRBStart","NumPRB","SymbolStart","NumSymbols", ...
    "MCS","Modulation","TargetCodeRate","NLayers","RV","MCSTable","TransformPrecoding","EnablePTRS"]);
[plan,allocator]=sixgr.mac.ra.buildCellRARResponsePlan( ...
    cellContext,policy,detections,receiverFS,state.GNBTemporaryCRNTIAllocator,used);
% This is still the legacy continuation adapter, not an independent cell
% Msg2 waveform producer. Keep its original RX-row identity without passing
% the UE checkpoint/index into the reusable cell plan builder.
plan.OriginalReceiverStageSHA256=localHash(receiverRow);
plan.ReceiverClockSource="original_matched_Msg1_receive_stage";
plan.PlanSHA256=localHash(rmfield(plan,'PlanSHA256'));
if ~plan.ResponseRequired
    checkpoint.Result.GNBResponseOwnedByCell=true;
    return; % Do not add a second coherent copy of the same cell response.
end
selected=find([plan.Assignments.RAPID]==det.DetectedPreambleIndex);
assert(isscalar(selected),'sixgr:truth:RARDetectionContextMismatch', ...
    'Legacy continuation candidate must occur in the original complete received detection set.');
assignment=plan.Assignments(selected);
[next,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',checkpoint, ...
    'StageAction','prepare_next_stage','GNBIdentityAssignment',assignment,'GNBResponsePlan',plan);
assert(~isempty(fieldnames(next.PreparedTransmission)) && ...
    next.PreparedTransmission.StageName=="Msg2", ...
    'sixgr:truth:RARAllocationWithoutTransmission','Commit the lease only with its actual prepared RAR.');
state.GNBTemporaryCRNTIAllocator=allocator;
checkpoint.Result.GNBResponseOwnedByCell=true;
end

function [fs,row]=localReceivedClock(cp)
T=sixgr.util.structGet(cp.Result,'RuntimeStageRows',table());
required=["RunId","UEId","AttemptId","CellId","StageSlot","StageName","Direction", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz","RxSampleCount"];
assert(istable(T) && all(ismember(required,string(T.Properties.VariableNames))), ...
    'sixgr:truth:RARReceiverClockRequired','An original completed Msg1 receive-stage clock is required; no Msg1 TX-clock fallback.');
r=cp.RAConfig;
for name=["RunId","StageName","Direction"]
    assert(isstring(T.(name)) && iscolumn(T.(name)) && all(~ismissing(T.(name))), ...
        'sixgr:truth:RARReceiverClockRequired','Receive-stage identity must retain original scalar text rows.');
end
for name=["UEId","AttemptId","CellId","StageSlot"]
    assert(isnumeric(T.(name)) && ~islogical(T.(name)) && isreal(T.(name)) && iscolumn(T.(name)), ...
        'sixgr:truth:RARReceiverClockRequired','Receive-stage numeric identity must not be text/coerced values.');
end
hit=string(T.StageName)=="Msg1" & string(T.Direction)=="UL" & ...
    string(T.RunId)==string(r.RunId) & T.UEId==r.UEId & T.AttemptId==r.AttemptId & ...
    T.CellId==r.CellId & T.StageSlot==r.PRACHAbsoluteSlot;
assert(nnz(hit)==1,'sixgr:truth:RARReceiverClockRequired', ...
    'Require exactly one original Msg1 receive row matching this continuation and received cell/occasion.');
row=T(hit,:); fs=row.ObservationSampleRateHz;
first=row.ObservationStartSample; last=row.ObservationEndSampleExclusive;
assert(localNumericScalar(fs) && isfinite(fs) && fs>0 && ...
    localNumericScalar(first) && localNumericScalar(last) && localNumericScalar(row.RxSampleCount) && ...
    isfinite(first) && isfinite(last) && first>=0 && first==fix(first) && last==fix(last) && ...
    last>first && row.RxSampleCount==last-first, ...
    'sixgr:truth:RARReceiverClockRequired','The retained actual received extent and sample clock must be complete.');
end
function localAssertAlignedInitialULBWP(cfg,ra)
common=sixgr.util.structGet(cfg,'UECommonCellConfiguration',struct());
if isstruct(common) && isscalar(common) && isempty(fieldnames(common)), return; end
assert(isstruct(common) && isscalar(common) && isfield(common,'InitialULBWP'), ...
    'sixgr:truth:RARInitialULBWPUnsupported','Malformed original common BWP authority cannot be ignored.');
b=common.InitialULBWP;
assert(isstruct(b) && isscalar(b) && all(isfield(b,["StartRB","SizeRB","SubcarrierSpacing_kHz","CyclicPrefix"])) && ...
    isfield(ra,'NStartGrid') && isequal(b.StartRB,ra.NStartGrid) && isequal(b.SizeRB,ra.NSizeGrid) && ...
    isequal(b.SubcarrierSpacing_kHz,ra.CarrierSCSkHz) && string(b.CyclicPrefix)==string(ra.CarrierCyclicPrefix), ...
    'sixgr:truth:RARInitialULBWPUnsupported', ...
    'Existing RAR preparation supports only carrier-aligned full initial UL BWP; do not reinterpret a decoded narrow/offset BWP.');
end
function projected=localProject(source,names)
assert(isstruct(source) && isscalar(source) && all(isfield(source,names)), ...
    'sixgr:mac:ra:InvalidCellRARPlanContext','Missing original cell/grant-policy operands.');
projected=struct();
for name=names, projected.(name)=source.(name); end
end
function h=localHash(value)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
function yes=localNumericScalar(value)
yes=isnumeric(value) && ~islogical(value) && isreal(value) && isscalar(value);
end
