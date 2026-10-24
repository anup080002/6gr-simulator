function [ok,evidence]=testSharedTXLinearReferencePolicyActivation()
% Real production initialization + one intentionally idle shared RF/channel
% slot. This is policy/ledger integration, not decoded PHY, CSI per-port
% attribution, power accuracy, hardware qualification or checkpoint repair.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml'));
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,-10);
cfg.run.rootRunFolder=root;
cfg.lls6g.energy_efficiency.enabled=false;
cfg.rf.txSpatialPowerEnabled=false;
cfg.rf.modeledRadiatedPower.Enabled=false;
cfg.outputs.continuousRawIQCaptureEnabled=false;
policy=struct('Enabled',false,'Model',"fixed_first_order_pa_identity_dac", ...
    'Classification',"optional_research_experiment", ...
    'RequirementClass',"IMPLEMENTATION_POLICY");
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
evidence=struct('Scope',"actual_original_owner_policy_activation_and_idle_RF_channel_slot", ...
    'DecodedPHYQualified',false,'CSIPortAttributionQualified',false, ...
    'PowerAccuracyQualified',false,'SourceFolder',string(root), ...
    'Enabled',[],'Disabled',[]);
for enabled=[false true]
    current=cfg; policy.Enabled=enabled; current.rf.txLinearReference=policy;
    folder=fullfile(root,char("enabled_"+string(enabled))); mkdir(folder);
    state=sixgr.truth.CoupledTruthRuntime.initialize(current,folder,multi,struct(),1);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,current,"DL",1,1,1,-10,12);
    state.CurrentServingIdx(:)=1;
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,current,{current});
    assert(owner.Events.NextSampleIndex==0 && owner.Physical.NextSampleIndex==0 && ...
        isempty(owner.Events.ExecutionTrace) && isempty(owner.Pending));
    initial=owner.Physical.readRFExecutionLedger();
    if enabled
        assert(~isempty(initial) && initial.OriginSample==0 && initial.EndSampleExclusive==0 && ...
            height(initial.Inventory)==4 && height(initial.Intervals)==0 && ...
            numel(initial.TXLinearReferenceLibrary)==2 && ...
            height(initial.TXLinearReferenceIntervals)==0 && ...
            ~initial.TXLinearReferenceCompleteFromOrigin);
        library=initial.TXLinearReferenceLibrary;
        assert(isequal(sort(string({library.EndpointID})),["gnb_1","ue_1"]) && ...
            all([library.OriginSample]==0));
        for item=library
            sixgr.rf.InstalledTXLinearReference.validateRegistration(item);
            assert(isequaln(item.Policy,policy));
        end
    else
        assert(isempty(initial),'Disabled-only owner must not create a diagnostic RF ledger.');
    end
    % No queued signal is invented: advanceSlot certifies an empty input
    % population, then invokes the actual retained RF/channel/noise owners.
    [state,completed]=owner.advanceSlot(state,current); %#ok<ASGLU>
    assert(isempty(completed) && ~isempty(owner.Events.ExecutionTrace) && ...
        owner.Events.NextSampleIndex>0 && ...
        owner.Physical.NextSampleIndex==owner.Events.NextSampleIndex);
    final=owner.Physical.readRFExecutionLedger();
    count=0;
    for index=1:numel(owner.Events.ExecutionTrace)
        execution=owner.Events.ExecutionTrace{index}.Execution;
        consumed=execution.ExecutedContributors;
        assert(numel(consumed)==2 && all(arrayfun(@(x) ...
            x.Receipt.CompleteContributorList && isempty(x.Receipt.Components),consumed)));
        assert(numel(execution.TXLinearReferences)==2*double(enabled));
        count=count+numel(execution.TXLinearReferences);
    end
    if enabled
        assert(isequaln(final.TXLinearReferenceLibrary,initial.TXLinearReferenceLibrary) && ...
            final.TXLinearReferenceCompleteFromOrigin && ...
            final.EndSampleExclusive==owner.Events.NextSampleIndex && ...
            height(final.TXLinearReferenceIntervals)==count && count>0 && ...
            all(final.Intervals.InputIsAllZero(final.Intervals.Role=="TX")) && ...
            all(final.TXLinearReferenceIntervals.OriginalOwnerBindingVerified) && ...
            all(final.TXLinearReferenceIntervals.PhysicalIntervalCommitted));
        evidence.Enabled=final;
    else
        assert(isempty(final));
        evidence.Disabled=struct('RFExecutionLedgerAvailable',false, ...
            'TXLinearReferenceReceiptCount',count,'ActualEndSampleExclusive',owner.Events.NextSampleIndex);
    end
end
save(fullfile(root,'tx_linear_reference_policy_activation.mat'),'evidence','-v7.3');
fprintf('SHARED_TX_LINEAR_REFERENCE_POLICY_ACTIVATION_PASS rows=%d decoded_PHY=0 accuracy=0 root=%s\n', ...
    height(evidence.Enabled.TXLinearReferenceIntervals),root);
ok=true;
end
