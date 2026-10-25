function ok=testCellRARResponsePlan()
% Declared received-detection boundary -> actual MAC RAR codec/lease plan.
% No native PRACH detector, RAR waveform, UE reception, or live access is
% executed here. Existing physical ownership tests cover those separately.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
f=@sixgr.mac.ra.buildCellRARResponsePlan;
[cellContext,policy,det,fs]=operands();
allocator=sixgr.mac.ra.RARIdentityAllocator([6200 6209]); original=allocator;
before=rng;
[plan,proposal]=f(cellContext,policy,det,fs,allocator,6200);
assert(isequaln(allocator,original) && isempty(allocator.Allocations) && isequal(before,rng));
assert(plan.ResponseRequired && ~plan.AllocatorCommitted && ~plan.PHYExecutionPerformed && ...
    ~plan.RuntimeAuthorityVerified && numel(proposal.Allocations)==2);
assert(isequal([plan.Assignments.RAPID],[3 11]) && ...
    isequal([plan.Assignments.TemporaryCRNTI],[6201 6202]) && ...
    isequal(plan.SortedDetectionSourceIndices,[2;1]) && isequaln(plan.OriginalDetections,det));
assert(plan.ReceiverSampleRateHz==fs && plan.PlanSHA256==hash(rmfield(plan,'PlanSHA256')));
assert(isequal([plan.ULGrants.PRBStart],[0 6]) && isequal([plan.ULGrants.NumPRB],[6 6]));
for k=1:2
    originalIndex=plan.SortedDetectionSourceIndices(k);
    timing=sixgr.phy.ra.resolveRARTimingAdvance( ...
        plan.TimingAdvance(k).TimingAdvanceCommand,policy.CarrierSCSkHz,fs);
    assert(plan.TimingAdvance(k).SampleRateHz==fs && ...
        plan.TimingAdvance(k).TimingOffsetSamples==det(originalIndex).PropagationTimingOffsetSamples && ...
        abs(plan.TimingAdvance(k).QuantizationResidualSamples)<=timing.StepSamples/2);
    decoded=sixgr.mac.ra.decodeMACRAR(plan.RAR.Responses(k).Bits,policy);
    assert(decoded.RAPID==plan.Assignments(k).RAPID && ...
        decoded.TemporaryCRNTI==plan.Assignments(k).TemporaryCRNTI && ...
        isequal(decoded.ULGrant.BitVector,plan.ULGrants(k).BitVector));
end
assert(plan.RAR.BitLength==128 && numel(plan.RAR.Responses)==2);
assert(isempty(intersect(plan.ULGrants(1).PRBStart+(0:5),plan.ULGrants(2).PRBStart+(0:5))));

% Repeated complete set: preserve assignments and emit no second RAR.
[repeat,unchanged]=f(cellContext,policy,det([2 1]),fs,proposal,6200);
assert(~repeat.ResponseRequired && isempty(fieldnames(repeat.RAR)) && ...
    isequaln(unchanged,proposal) && isequal([repeat.Assignments.RAPID],[3 11]));
reject(@()f(cellContext,policy,det(1),fs,proposal,6200),'sixgr:truth:RARDetectionSetChanged');
mixed=det; mixed(1).DetectedPreambleIndex=20;
reject(@()f(cellContext,policy,mixed,fs,proposal,6200),'sixgr:truth:RARDetectionSetChanged');
different=det(1); different.DetectedPreambleIndex=20;
reject(@()f(cellContext,policy,different,fs,proposal,6200),'sixgr:truth:RARMultiResponseMultiplexingRequired');
duplicate=det([1 1]);
reject(@()f(cellContext,policy,duplicate,fs,allocator,6200),'sixgr:mac:ra:DuplicateRARRAPID');
[empty,noLeases]=f(cellContext,policy,struct([]),fs,allocator,6200);
assert(~empty.ResponseRequired && isempty(fieldnames(empty.RAR)) && isequaln(noLeases,allocator));

% Leases are cell scoped. Preserve the established standalone PCI0/endpoint0
% namespace; neither path invents a UE or uses one to choose an identity.
otherCell=cellContext; otherCell.ServingCell=4;
[other,~]=f(otherCell,policy,det,fs,proposal,6200);
assert(other.Assignments(1).TemporaryCRNTI==6201);
zero=cellContext; zero.ServingCell=0; zero.CellId=0;
[zeroPlan,~]=f(zero,policy,det,fs,allocator,[]); assert(zeroPlan.ResponseRequired);
poison=cellContext; poison.UEId=1;
reject(@()f(poison,policy,det,fs,allocator,[]),'sixgr:mac:ra:InvalidCellRARPlanContext');
poison=policy; poison.Checkpoint=struct();
reject(@()f(cellContext,poison,det,fs,allocator,[]),'sixgr:mac:ra:InvalidCellRARPlanContext');

% Failed detector/clock/timing/codec plans cannot mutate the caller's leases.
% A wide grid must not let text '0' become numeric PRB 48 before validation.
for field={ 'PRBStart','NumPRB' }
    for value={ '0',"0",true,NaN,Inf,[0 1],complex(1,1),0.5,-1 }
        malformed=policy; malformed.NSizeGrid=106;
        malformed.Msg3PUSCH.(field{1})=value{1};
        reject(@()f(cellContext,malformed,det,fs,allocator,[]), ...
            'sixgr:mac:ra:InvalidCellRARPlanContext');
    end
end
bad=det; bad(1).Detected=false;
reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:mac:ra:RARUnacceptedDetection');
bad=rmfield(det,'Detected');
reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:mac:ra:RARUnacceptedDetection');
for value={NaN,true,'0',[0 1],complex(1,1),-1}
    bad=det; bad(1).PropagationTimingOffsetSamples=value{1};
    reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:truth:RARMissingMeasuredTiming');
end
for value={true,'0',[0 1],complex(1,1),Inf}
    bad=det; bad(1).TimingOffsetSamples=value{1};
    reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:truth:RARMissingMeasuredTiming');
end
for value={NaN,true,'30720000',[fs fs],complex(fs,1),0}
    reject(@()f(cellContext,policy,det,value{1},allocator,[]),'sixgr:truth:RARReceiverClockRequired');
end
bad=det; [bad.SampleRateHz]=deal(fs/2);
reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:truth:RARDetectionContextMismatch');
bad=det; [bad.CellId]=deal(cellContext.CellId+1);
reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:truth:RARDetectionContextMismatch');
step=sixgr.phy.ra.resolveRARTimingAdvance(0,policy.CarrierSCSkHz,fs);
bad=det; bad(1).PropagationTimingOffsetSamples=3847*step.StepSamples;
reject(@()f(cellContext,policy,bad,fs,allocator,[]),'sixgr:phy:ra:PRACHTimingOutsideRARRange');
wide=policy; wide.Msg3PUSCH.NumPRB=wide.NSizeGrid;
reject(@()f(cellContext,wide,det,fs,allocator,[]),'sixgr:truth:RARMsg3CapacityExceeded');
small=sixgr.mac.ra.RARIdentityAllocator([6200 6200]);
reject(@()f(cellContext,policy,det,fs,small,[]),'sixgr:mac:ra:TemporaryCRNTIPoolExhausted');
assert(isequaln(original,allocator) && isempty(small.Allocations));

% Declared adapter boundary: actual wrapper must first use this original
% matched RX clock, then reach the real continuation validator. Deliberately
% missing continuation fields stop before any PHY preparation, exercising
% transactional failure (NOT an actual successfully prepared waveform).
[state,cfg,cp]=declaredWrapperBoundary(cellContext,policy,det,fs,allocator);
stateBefore=state;
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,cp),'sixgr:phy:ra:InvalidRAContinuation');
assert(isequaln(state,stateBefore) && isempty(state.GNBTemporaryCRNTIAllocator.Allocations));
bad=cp; bad.Result.RuntimeStageRows.ObservationSampleRateHz=NaN;
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,bad),'sixgr:truth:RARReceiverClockRequired');
bad=cp; bad.Result.RuntimeStageRows=[bad.Result.RuntimeStageRows;bad.Result.RuntimeStageRows];
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,bad),'sixgr:truth:RARReceiverClockRequired');
bad=cp; bad.Result.RuntimeStageRows.CellId=cellContext.CellId+1;
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,bad),'sixgr:truth:RARReceiverClockRequired');
bad=cp; bad.Result.RuntimeStageRows.RxSampleCount=char(48);
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,bad),'sixgr:truth:RARReceiverClockRequired');
bad=cp; bad.Result.RuntimeStageRows.RunId=1;
reject(@()sixgr.truth.prepareCellRARResponse(state,cfg,bad),'sixgr:truth:RARReceiverClockRequired');
badCfg=cfg; badCfg.UECommonCellConfiguration.InitialULBWP.StartRB=1;
reject(@()sixgr.truth.prepareCellRARResponse(state,badCfg,cp),'sixgr:truth:RARInitialULBWPUnsupported');
fprintf('CELL_RAR_RESPONSE_PLAN_PASS declared_detections=2 actual_MAC_RAR_codecs=2 PHY_execution=0\n');
ok=true;
end
function [cellContext,policy,det,fs]=operands()
cellContext=struct('ServingCell',2,'CellId',17,'PRACHAbsoluteSlot',3, ...
    'PRACHOccasionSymbol',0,'PRACHFrequencyIndex',1,'RARNTI',1135);
policy=struct('NSizeGrid',24,'CarrierSCSkHz',15,'CarrierCyclicPrefix',"normal", ...
    'RARGrantConfig',struct('field_layout',"licensed_27bit",'frequency_hopping',false, ...
    'time_resource_assignment',0,'tpc_command',3), ...
    'Msg3PUSCH',struct('PRBStart',0,'NumPRB',6,'SymbolStart',0,'NumSymbols',14, ...
    'MCS',0,'Modulation',"QPSK",'TargetCodeRate',120/1024,'NLayers',1,'RV',0, ...
    'MCSTable',"qam64",'TransformPrecoding',false,'EnablePTRS',false));
det=repmat(struct('Detected',true,'DetectedPreambleIndex',11, ...
    'TimingOffsetSamples',40.25,'PropagationTimingOffsetSamples',32.25, ...
    'RAPIDMatchesTx',false,'Source',"DECLARED_detection_boundary_not_PRACH_RX"),2,1);
det(2).DetectedPreambleIndex=3; det(2).PropagationTimingOffsetSamples=64.5;
fs=30.72e6;
end
function [state,cfg,cp]=declaredWrapperBoundary(c,p,d,fs,a)
ra=c; for name=string(fieldnames(p)).', ra.(name)=p.(name); end
ra.RunId="declared_plan_boundary"; ra.UEId=7; ra.AttemptId=2; ra.NStartGrid=0;
row=struct('RunId',ra.RunId,'UEId',ra.UEId,'AttemptId',ra.AttemptId,'CellId',ra.CellId, ...
    'StageSlot',ra.PRACHAbsoluteSlot,'StageName',"Msg1",'Direction',"UL", ...
    'ObservationStartSample',100,'ObservationEndSampleExclusive',148,'ObservationSampleRateHz',fs,'RxSampleCount',48);
det=d(1); det.Detections=d;
cp=struct('NextStage',2,'ResumePhase',"decoded",'RAConfig',ra,'Detection',det, ...
    'Result',struct('PreambleDetected',true,'RuntimeStageRows',struct2table(row,'AsArray',true)));
state=struct('GNBTemporaryCRNTIAllocator',a);
cfg=struct('random_access',struct('temporary_crnti_pool',a.Pool), ...
    'UECommonCellConfiguration',struct('InitialULBWP',struct('StartRB',0,'SizeRB',p.NSizeGrid, ...
    'SubcarrierSpacing_kHz',p.CarrierSCSkHz,'CyclicPrefix',p.CarrierCyclicPrefix)));
end
function h=hash(value)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
function reject(fn,id)
try
    fn();
catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingCellRARPlanRejection','Expected %s.',id);
end
