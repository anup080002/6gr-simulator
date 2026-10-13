function ok=testCellCommonSIB1Broadcast()
% Two receivers consume one physical cell burst, including all authored SI
% beam occasions. This is bounded physical access, not a full data run.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
root=fullfile(pwd,'results','lls','cell_common_sib1', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
cfg.run.rootRunFolder=root;
assert(cfg.phy.sib1.transmissionScope=="all_active_ssb_occasions");
m=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,m,struct(),9);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
prototypes=cell(1,2); configs=cell(1,2);
for ue=1:2
    [current,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,ue,'DL');
    % Deliberately different receive/candidate hints must not select the
    % cell's physical SI beam set. No receiver gets transmitted payload bits.
    current.phy.ssb.runtimeSSBIndex=ue-1;
    prototype=sixgr.link.runCellSearch_MIB_SIB1(current,'PrepareOnly',true, ...
        'UseRuntimeChannel',true,'RuntimeSlot',0);
    assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
    p=prototype.PreparedBroadcast;
    assert(isequal(p.Tx.SIB1TransmitSSBIndices0Based,0:3) && numel(p.Tx.SIB1Transmissions)==4);
    assert(isequal([p.Tx.SIB1Transmissions.SIB1AbsoluteSlot],5:8));
    for si=p.Tx.SIB1Transmissions
        exact=sixgr.link.broadcastSIB1WaveformPortGrid(si);
        active=find(reshape(any(any(exact~=0,1),3),[],1));
        absolute=si.SIB1AbsoluteSlot*si.Carrier.SymbolsPerSlot+active-1;
        [present,column]=ismember(absolute,p.TxInfo.PortGridAbsoluteSymbolIndices);
        assert(all(present) && isequal(p.TxInfo.PortGrid(:,column,:),exact(:,active,:)), ...
            'test:MissingSIBeamPower','Every emitted SI beam must contribute its exact grid to power normalization.');
    end
    if ue==1
        first=p;
    else
        assert(isequal(first.TransmitSamples,p.TransmitSamples), ...
            'test:PerUECellBroadcast','One configured cell broadcast must have identical physical samples for every UE.');
        assert(isequal(first.TxInfo.PortGrid,p.TxInfo.PortGrid));
    end
    context=struct('Config',current,'Slot',1,'Frame',1,'RNTI',ue, ...
        'ServingCell',1,'SNR',20,'Prototype',prototype);
    stream.queueDownlink('PBCH',ue,p,context);
    prototypes{ue}=prototype; configs{ue}=current;
end
% Every transmitted SI occasion is reserved from competing common data.
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
plan.validateSIB1References();
allocation=struct('PRBStart',0,'NumPRB',24,'SymbolStart',2,'NumSymbols',7);
for slot0=5:8
    [available,ownership]=plan.checkPDSCH(allocation,slot0);
    assert(~available && any(ownership.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));
end
% Verify the original physical invariant still rejects a changed producer.
bad=p; bad.TransmitSamples(1,1)=bad.TransmitSamples(1,1)+1;
try
    stream.queueDownlink('PBCH',2,bad,context);
    error('test:MissingCellBroadcastGuard','Changed cell samples were accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InconsistentCellBroadcast'));
end
rows=struct([]);
lastSlot=ceil(first.NumSamples/(first.SampleRateHz*state.SlotDuration_s));
for slot=1:lastSlot
    state.CurrentSlot=slot;
    [state,completed]=stream.advanceSlot(state,cfg);
    for item=completed
        if item.Kind~="PBCH", continue; end
        ue=item.UE;
        [~,pre,txObs,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        prototype=prototypes{ue}; prepared=prototype.PreparedBroadcast;
        prototype.RuntimeChannelReplay=replay;
        prototype.RuntimeDLChannelState=stream.channelState(ue,'DL');
        prototype.PowerContext=prepared.PowerContext;
        prototype.RuntimeChannelStateUsed=true;
        options=struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
            'CandidateSSBIndices',0:3,'SSBIndex',[],'WriteArtifacts',false, ...
            'RunFolder','','RunId','cell_common_sib1', ...
            'PhysicalMeasurementObservation',pre,'TransmitObservation',txObs);
        received=sixgr.link.completeCellSearchBroadcast(prepared,post,prototype,options,tic);
        save(fullfile(root,sprintf('ue_%d.mat',ue)),'received');
        observed=sixgr.truth.buildObservedBroadcastREAllocation(prepared,txObs,1);
        siRows=observed(observed.rnti==65535,:);
        assert(isequal(unique(siRows.associated_ssb_index0).',0:3), ...
            'Every emitted SI beam must be represented in committed resource exports.');
        writetable(observed,fullfile(root,sprintf('ue_%d_committed_resources.csv',ue)));
        for candidate=received.CandidateResults
            r=candidate{1};
            row=struct('UE',ue,'SSBIndex',r.SSBIndex,'Passed',r.Ok, ...
                'FailureReason',string(r.FailureReason));
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
        writetable(struct2table(rows),fullfile(root,'receiver_cases.csv'));
    end
end
capture=stream.finalizeContinuousTxIQCapture(stream.Events.NextSampleIndex,lastSlot);
save(fullfile(root,'continuous_capture.mat'),'capture');
assert(numel(rows)==8 && all([rows.Passed]), ...
    'test:CellCommonSIB1Reception','Both receivers must decode all four independently searched SI occasions.');
save(fullfile(root,'configuration.mat'),'cfg');
fprintf('CELL_COMMON_SIB1_BROADCAST_PASS %s\n',root);
ok=true;
end
