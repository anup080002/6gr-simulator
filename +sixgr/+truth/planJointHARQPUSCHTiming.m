function [state,dlGrants,ulGrants]=planJointHARQPUSCHTiming(state,userCfg,dlGrants,ulGrants)
% Finalize tentative DL/UL timing before either DCI is queued. Existing
% physical gNB control transmissions are immutable scheduling obligations,
% including DCIs that the UE missed. No UE ACK/pending-payload oracle is used.
owner=state.SharedWaveformStream;
registered=owner.readTransmittedSchedulingControls();
priorDL={}; priorUL={};
for k=1:numel(registered)
    r=registered{k}; g=r.Binding.Grant;
    if ~any(string(r.Binding.Direction)==["DL","UL"]), continue; end
    assert(isa(r.TransmitObservation,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
        r.TransmitObservation.isComplete() && r.AvailableAtSample<=owner.Events.NextSampleIndex, ...
        'sixgr:truth:JointTimingAfterControlEnqueue', ...
        'Joint planning must precede current-occasion DCI enqueue; prior controls need physical TX evidence.');
    if string(r.Binding.Direction)=="DL", priorDL{end+1}=g; %#ok<AGROW>
    else, priorUL{end+1}=g; end %#ok<AGROW>
end
rows=table(); keep=true(size(ulGrants));
% A newly proposed UL grant cannot invalidate a DL DCI sent earlier.
for ui=1:numel(ulGrants)
    u=ulGrants(ui);
    for di=1:numel(priorDL)
        g=priorDL{di};
        if ~localOverlap(g,u), continue; end
        c=sixgr.truth.buildHARQPUSCHTimingConstraints(userCfg{g.UEIndex},g,u);
        [valid,reason]=sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(g.TimingDecision.HARQACKDecision,c);
        if ~valid
            keep(ui)=false;
            state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state,u,'UL');
            rows=[rows;localRow(g,g.K1,NaN,"defer_tentative_UL",reason)]; %#ok<AGROW>
            break;
        end
    end
end
ulGrants=ulGrants(keep);
allUL=[priorUL,reshape(num2cell(ulGrants),1,[])];
keep=true(size(dlGrants));
for di=1:numel(dlGrants)
    g=dlGrants(di); old=g;
    constraints=sixgr.truth.buildHARQPUSCHTimingConstraints(userCfg{g.UEIndex},g,allUL);
    if isempty(constraints), continue; end
    g.HARQACKPUSCHTimingConstraints=constraints;
    g.K1=NaN; % Select from the authored list, never slide an issued DCI.
    scheduler=state.DLSchedulers{g.ServingCell};
    decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(scheduler.Cfg,g);
    if ~decision.Valid
        reason=string(decision.ReasonCode);
        assert(sixgr.truth.isDeferrableCoupledHARQACKTimingDecision(decision) || ...
            startsWith(reason,"harq_ack_timing_rejected:insufficient_harq_pusch_"), ...
            'sixgr:truth:JointHARQTimingInvalid','Joint scheduling rejected malformed timing: %s',reason);
        keep(di)=false;
        state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state,old,'DL');
        rows=[rows;localRow(old,old.K1,NaN,"defer_tentative_DL",reason)]; %#ok<AGROW>
        continue;
    end
    g=scheduler.attachCanonicalTimingDecision(g);
    g=scheduler.freezePHYGrantForGrant(g,'TimingAlreadySelected',true);
    assert(isequaln(g.TimingDecision.DataDecision,old.TimingDecision.DataDecision) && ...
        isequaln(g.SymbolAllocation,old.SymbolAllocation) && isequaln(g.PRBSet,old.PRBSet) && ...
        isequaln(g.TBSBits,old.TBSBits) && isequaln(g.HARQ,old.HARQ), ...
        'sixgr:truth:JointTimingChangedDataContract', ...
        'K1 selection must preserve the existing data occasion, allocation, real TB size and HARQ identity.');
    g.DCI=scheduler.buildDCIBitfield(g);
    for name=string(fieldnames(g)).', dlGrants(di).(name)=g.(name); end
    rows=[rows;localRow(g,old.K1,g.K1,"admit_joint_timing","configured_K1_and_allocation_processing")]; %#ok<AGROW>
end
dlGrants=dlGrants(keep);
if ~isempty(rows)
    previous=sixgr.util.structGet(state,'ControlTrials.JointHARQPUSCHTimingDecisions',table());
    state.ControlTrials.JointHARQPUSCHTimingDecisions=[previous;rows];
end
end

function tf=localOverlap(dl,ul)
tf=false;
if dl.UEIndex~=ul.UEIndex || dl.ServingCell~=ul.ServingCell || ...
        ~dl.TimingDecision.HARQACKRequired, return; end
d=dl.TimingDecision.HARQACKDecision; u=ul.TimingDecision.DataDecision;
tf=d.TargetTick<u.TargetEndTick && u.TargetTick<d.TargetEndTick;
end

function row=localRow(g,oldK1,newK1,action,reason)
row=table(double(g.UEIndex),double(g.ServingCell),double(g.Slot), ...
    double(oldK1),double(newK1),string(action),string(reason), ...
    "before_current_DL_and_UL_DCI_enqueue", ...
    'VariableNames',{'UEIndex','ServingCell','DLSourceSlot','PriorCandidateK1', ...
    'SelectedK1','Action','Reason','DecisionStage'});
end
