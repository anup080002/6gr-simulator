function ok=testSchedulerReceivedULTiming()
% Analytical received-TAG fixtures: scheduler wiring, not access/PHY truth.
setup6GRSimToolkit('Verbose',false);
for mode=["TDD","FDD"]
    file='lls_causal_access_to_data_wiring_tdd.yaml';
    if mode=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    if mode=="TDD", tddCfg=cfg; end
    carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
    for direction=["DL","UL"]
        control=5; if direction=="UL", control=8; end
        name='pdsch'; if direction=="UL", name='pusch'; end
        allocation=cfg.phy.(name).symbolAllocation;
        grant=struct('Direction',direction,'RNTI',1,'ControlAbsoluteSlot',control, ...
            'SymbolAllocation',allocation,'HARQProcessID',0);
        for command=[0 3]
            ctx=localContext(ofdm.SampleRate,carrier.SubcarrierSpacing,command,carrier.NCellID);
            ue=struct('RNTI',1,'SharedULTimingRequired',true,'SharedULTimingContext',ctx);
            g=sixgr.l2.mac.attachReceivedULTimingAuthority(grant,ue);
            for type=["PF","RR"]
                ctor=str2func('sixgr.l2.mac.Scheduler'+type);
                scheduler=ctor(cfg,'Direction',direction);
                bound=scheduler.attachCanonicalTimingDecision(g);
                e=bound.ReceivedULTimingValidation;
                assert(bound.TimingDecision.Valid && e.OriginsResolved && ~e.WaveformTimingApplied);
                assert(bound.TimingAdvanceTicks==ctx.ReceivedRARTiming.NTA_Tc+ctx.Offset.NTAOffset_Tc && ...
                    e.TotalAdvanceTicks==bound.TimingAdvanceTicks && bound.TimingAdvanceOwnerRNTI==ue.RNTI);
                if direction=="UL", r=bound.TimingDecision.DataDecision;
                else, r=bound.TimingDecision.HARQACKDecision; end
                assert(r.WaveformPlacementTick==r.TargetTick-bound.TimingAdvanceTicks);
                expired=g; expired.SharedULTimingContext.TimeAlignmentExpirySampleExclusive=e.TransmitEndSampleExclusive-1;
                localReject(@()scheduler.attachCanonicalTimingDecision(expired),'sixgr:link:ConnectedULAfterTAExpiry');
                future=g; future.SharedULTimingContext.TimingAdvanceEffectiveAtSample=e.TransmitStartSample+1;
                localReject(@()scheduler.attachCanonicalTimingDecision(future),'sixgr:link:ConnectedULBeforeTAApplication');
                wrong=g; wrong.TimingAdvanceTicks=wrong.TimingAdvanceTicks+int64(1);
                localReject(@()scheduler.attachCanonicalTimingDecision(wrong),'sixgr:l2:mac:ReceivedULTimingDecisionMismatch');
            end
            missing=ue; missing.SharedULTimingContext=struct();
            localReject(@()sixgr.l2.mac.attachReceivedULTimingAuthority(grant,missing),'sixgr:l2:mac:MissingReceivedULTiming');
            other=ue; other.RNTI=2;
            localReject(@()sixgr.l2.mac.attachReceivedULTimingAuthority(grant,other),'sixgr:l2:mac:ReceivedULTimingOwnerMismatch');
        end
    end
    fprintf('[PASS] %s per-UE received timing at PF/RR UL-data and DL-ACK boundaries.\n',mode);
end

% Actual PF/RR scheduling and grant/DCI freeze with distinct UE commands.
% This explicit FDD catalog tests metadata/packing, not a main FDD run.
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.phy.synchronization.maxTimingUncertaintySamples=32;
% Explicit receiver-known TDRA rows for the two allocations below.
cfg.phy.pdsch.timeDomainAllocations=[0 0 14 1;1 2 12 1];
cfg.phy.pusch.timeDomainAllocations=[0 0 14 1;1 2 12 1;2 0 14 2;3 2 12 2];
cfg.mac.scheduler.maxUEPerSlot=2; cfg.mac.scheduler.minPRBPerUE=4;
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
ue=repmat(struct('RNTI',1,'DLBufferBytes',1800,'ULBufferBytes',1800,'CQI',8, ...
    'RI',1,'HeadOfLineDelay_ms',1,'SharedULTimingRequired',true,'SharedULTimingContext',struct()),2,1);
for k=1:2
    ue(k).RNTI=k;
    ue(k).SharedULTimingContext=localContext(ofdm.SampleRate,carrier.SubcarrierSpacing,3*(k-1),carrier.NCellID);
end
for direction=["DL","UL"]
    for type=["PF","RR"]
        ctor=str2func('sixgr.l2.mac.Scheduler'+type); scheduler=ctor(cfg,'Direction',direction);
        % Explicitly test the earlier K2=1 candidate. The baseline now
        % selects K2=2 because first-symbol data requires N2+d2,1.
        % Received advance must not rescue an infeasible earlier candidate.
        if direction=="UL"
            tight=cfg; tight.phy.frameStructure.TimingContext.Policy.SelectedK2=1;
            tightScheduler=ctor(tight,'Direction',direction);
            localReject(@()tightScheduler.schedule(8,ue,struct('NPRB',40,'SymbolAllocation',[0 14])), ...
                'sixgr:SchedulerBase:TimingDecisionRejected');
            scheduler=ctor(cfg,'Direction',direction);
        end
        [grants,~]=scheduler.schedule(8,ue,struct('NPRB',40,'SymbolAllocation',[2 12]));
        assert(numel(grants)==2,'Both nonempty UE queues must exercise per-UE binding.');
        for g=reshape(grants,1,[])
            owner=ue([ue.RNTI]==g.RNTI);
            expected=owner.SharedULTimingContext.ReceivedRARTiming.NTA_Tc+owner.SharedULTimingContext.Offset.NTAOffset_Tc;
            assert(g.PHYGrant.IsFrozen && g.TimingAdvanceTicks==expected && ...
                g.ReceivedULTimingValidation.TotalAdvanceTicks==expected && ...
                isequaln(g.SharedULTimingContext,owner.SharedULTimingContext) && ~isempty(g.DCI.Bits));
        end
    end
end

% Received clock ownership must follow the serving cell, not scenario PCI.
ctx=localContext(ofdm.SampleRate,carrier.SubcarrierSpacing,3,7);
state=struct('Layout',struct('bs',struct('nCellId',[7 8])), ...
    'ConnectedULTimingByUE',{{ctx}},'UECommonCellConfigurationByUE', ...
    {{struct('InitialULBWP',struct('SubcarrierSpacing_kHz',carrier.SubcarrierSpacing))}});
actual=sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime(state,1,1);
assert(isequaln(actual,ctx));
localReject(@()sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime(state,1,2), ...
    'sixgr:truth:ReceivedULTimingServingCellMismatch');
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=2*carrier.SubcarrierSpacing;
localReject(@()sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime(state,1,1), ...
    'sixgr:truth:ConnectedULTimingBWPChanged');

% Exercise the main runtime's UE-state and execution-config adapters with
% an analytical initial context. No access waveform is claimed here; the
% actual shared owner is initialized but must not consume physical samples.
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(tddCfg,tempname,multi,struct(),1);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[runtime,owner]=sixgr.truth.CoupledWaveformStream.initialize(runtime,tddCfg,{tddCfg});
carrier=sixgr.phy.grid.makeCarrier(tddCfg);
ctx=localContext(owner.SampleRateHz,carrier.SubcarrierSpacing,3,runtime.Layout.bs.nCellId(1));
ctx.DLReference.AvailableAtSample=0;
ctx.TimingAdvanceAvailableAtSample=0; ctx.TimingAdvanceEffectiveAtSample=0;
runtime.ConnectedULTimingByUE={ctx};
runtime.UECommonCellConfigurationByUE={struct('InitialULBWP', ...
    struct('SubcarrierSpacing_kHz',carrier.SubcarrierSpacing))};
[cfgU,runtime]=sixgr.truth.CoupledTruthRuntime.applyUserContext(tddCfg,runtime,1,'UL');
[runtime,ueState]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(runtime,tddCfg,1,'UL',1);
assert(isequaln(cfgU.SharedULTimingContext,ctx) && ...
    isequaln(ueState.SharedULTimingContext,ctx) && ueState.SharedULTimingRequired && ...
    ~ueState.Active && owner.Events.NextSampleIndex==0);
future=runtime; future.ConnectedULTimingByUE{1}.TimingAdvanceAvailableAtSample=1;
localReject(@()sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime(future,1,1), ...
    'sixgr:truth:FutureReceivedULTiming');
runtime.ConnectedULTimingByUE={[]};
[cleared,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgU,runtime,1,'UL');
assert(~isfield(cleared,'SharedULTimingContext'),'A missing UE TAG must not inherit stale caller context.');
ok=true;
disp('SCHEDULER_RECEIVED_UL_TIMING_PASS: analytical TAG/real grant freeze; no main-run claim.');
end

function ctx=localContext(fs,scs,command,ncell)
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
ctx=struct('DLReference',struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',1000,'NCellID',ncell), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(command,scs,fs), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'TimingAdvanceAvailableAtSample',1000,'TimingAdvanceEffectiveAtSample',2000, ...
    'TimeAlignmentExpirySampleExclusive',Inf);
end
function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
