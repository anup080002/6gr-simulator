function state=queuePreparedSharedDataPlan(state,cfg,multiUser,plan,direction,snr)
% Preserve one original grant while an earlier bearer transmission awaits commit.
[state,deferred]=sixgr.truth.deferSharedDataPreparation(state,cfg,multiUser,plan,direction,snr);
if deferred, return; end
if upper(string(direction))=="DL" && isfield(state,'SharedWaveformStream') && ...
        logical(sixgr.util.structGet(plan.Cfg,'phy.csirs.enable',false))
    plan.Cfg=sixgr.util.structSet(plan.Cfg, ...
        'lls6g.runtime.independentCellCommonCSIRSOwner',true);
end
if upper(string(direction))=="UL" && isfield( ...
        sixgr.util.structGet(plan.Cfg,'phy.pdcch.operatorControl',struct()),'connected_dci')
    controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
    key=sixgr.truth.GrantPreparation.sharedGrantControlKey(plan.GrantSnapshot,direction);
    hit=find(cellfun(@(x)x.Key==key,controls));
    assert(numel(hit)==1 && controls{hit}.Allowed && ...
        controls{hit}.AvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex && ...
        ~isempty(fieldnames(controls{hit}.ReceivedAssignment)), ...
        'sixgr:truth:MissingReceivedULAssignment', ...
        'Connected UE transmission requires its accepted received DCI, not the scheduled grant alone.');
    plan.Cfg.phy.pusch.receivedDCIAssignment=controls{hit}.ReceivedAssignment;
    ueBuffers=sixgr.util.structGet(state,'SharedUEULHARQBuffers',{});
    if numel(ueBuffers)<plan.UEIndex || isempty(ueBuffers{plan.UEIndex})
        ueBuffers{plan.UEIndex}=sixgr.link.ReceivedULHARQState(plan.Cfg);
    end
    plan.Cfg.phy.pusch.receivedHARQState=ueBuffers{plan.UEIndex};
    if logical(sixgr.util.structGet(plan.Cfg,'phy.pusch.powerControl.enabled',false))
        powerStates=sixgr.util.structGet(state,'SharedUEULPowerControlStates',{});
        if numel(powerStates)<plan.UEIndex || isempty(powerStates{plan.UEIndex})
            powerStates{plan.UEIndex}=sixgr.link.ReceivedULPowerControlState(plan.Cfg);
        end
        plan.Cfg.phy.pusch.receivedPowerControlState=powerStates{plan.UEIndex};
        plan.Cfg.phy.pusch.receivedTPCObservation=struct( ...
            'AssignmentDigest',controls{hit}.ReceivedAssignment.AssignmentDigest, ...
            'AvailableAtSample',controls{hit}.AvailableAtSample, ...
            'SampleRateHz',state.SharedWaveformStream.SampleRateHz);
    end
end
if logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false))
    [plan,state]=sixgr.truth.bindProtocolPayloadsToGrantCache(plan,state,cfg,direction);
end
if upper(string(direction))=="UL" && logical(sixgr.util.structGet(plan.Cfg,'phy.mac.uplinkControl.Enabled',false))
    [state,plan]=sixgr.truth.prepareSharedULMAC(state,plan);
end
plan.TrialContext.PrepareOnly=true;
plan.Cfg=sixgr.truth.bindPreparedDataPopulation(plan.Cfg,state, ...
    plan.GrantSnapshot,plan.UEIndex,direction,snr);
job=sixgr.truth.GrantPreparation.buildJob(plan.Cfg,direction,snr, ...
    plan.GrantSnapshot.Frame,plan.LinkAdaptationStateIn,plan.TrialContext);
jobResult=sixgr.truth.executeGrantPHYJob(job);
output=jobResult.Result;
assert(isfield(output,'PreparedTransmission'),'sixgr:truth:MissingPreparedData','No retained data waveform was produced.');
context=struct('Plan',plan,'Job',job,'MultiUser',multiUser,'Config',cfg, ...
    'Key',sixgr.truth.GrantPreparation.sharedGrantControlKey(plan.GrantSnapshot,direction));
if upper(string(direction))=="UL" && ...
        isfield(plan.Cfg.phy.pusch,'priorityIndex')
    pendingSRS=state.SharedWaveformStream.Pending( ...
        string({state.SharedWaveformStream.Pending.Kind})=="SRS" & ...
        [state.SharedWaveformStream.Pending.UE]==plan.UEIndex);
    for pendingIndex=1:numel(pendingSRS)
        sixgr.phy.frame.validatePreparedPriorityZeroPUSCHSRS( ...
            pendingSRS(pendingIndex).Context.Prepared, ...
            output.PreparedTransmission);
    end
end
state.SharedWaveformStream.queueData(plan.UEIndex,output.PreparedTransmission,context);
if isfield(output,'UEHARQState')
    ueBuffers{plan.UEIndex}=output.UEHARQState;
    state.SharedUEULHARQBuffers=ueBuffers;
end
if isfield(output,'UEPowerControlState')
    % Commit on actual TX queue admission, not on eventual gNB CRC.
    powerStates{plan.UEIndex}=output.UEPowerControlState;
    state.SharedUEULPowerControlStates=powerStates;
end
end
