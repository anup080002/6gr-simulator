function ok=testTwoUESRSConfiguredCadence()
% Exact target YAML calendar plus received, separated four-port SRS.
% Known-access state below tests scheduling only. It is not an attach result.
% The controlled flat-channel waveform is not full multi-UE qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.srs.maxUEsPerSlot==2 && ...
    string(cfg.phy.srs.schedulingPolicy)=="multiplex_due_users", ...
    'test:TwoUESRSCapacity','Both configured UEs need their five-slot sounding opportunity.');
period=cfg.phy.srs.period_slots;
age=cfg.run.controlGating.srsMaxAgeSlots;
assert(period==5 && age==5 && cfg.run.controlGating.srsRequired && ...
    cfg.phy.srs.nPorts==4 && cfg.channel.nRxAnt==4, ...
    'Keep the original age guard, sounding ports and receiver dimensions.');
plan=struct('CurrentSlot',1,'PlanningDecisionSlot',1,'NumUsers',2, ...
    'SRSSlotPeriod',period,'LastSRSSlotByUE',[0;0], ...
    'LastSuccessfulPRACHSlotByUE',[1;1],'AccessState',["succeeded";"succeeded"], ...
    'ControlGating',struct('SRSRequired',true,'PRACHRequired',true));
due=false(80,2); oldDue=due;
old=cfg; old.phy.srs.maxUEsPerSlot=1;
old.phy.srs.schedulingPolicy='round_robin_phase';
for slot=2:80
    plan.CurrentSlot=slot; plan.PlanningDecisionSlot=slot-1;
    for ue=1:2
        due(slot,ue)=sixgr.truth.coupledSRSAttemptDue(plan,cfg,slot,ue);
        oldDue(slot,ue)=sixgr.truth.coupledSRSAttemptDue(plan,old,slot,ue);
    end
end
expected=mod((1:80).',period)==0;
assert(isequal(due,repmat(expected,1,2)), ...
    'Each UE must be due on configured UL occasions, never on intervening slots.');
assert(all(diff(find(oldDue(:,1)))==2*period) && ...
    all(diff(find(oldDue(:,2)))==2*period) && 2*period>age, ...
    'Retain the old cadence/age mismatch as a negative scheduling comparison.');
for ue=1:2
    assert(all(diff(find(due(:,ue)))<=age));
end
plan.CurrentSlot=5; plan.PlanningDecisionSlot=4;
plan.LastSuccessfulPRACHSlotByUE(:)=5;
assert(~sixgr.truth.coupledSRSAttemptDue(plan,cfg,5,1), ...
    'A future access success must not become prior SRS scheduling authority.');

% Execute the exact configured combs/ports through the production SRS RX.
% Channel and noise truth are supplied to the source/scorer only, not RX.
receiveCfg=cell(1,2); refs=cell(1,2); grids=cell(1,2);
channels={diag([1 .8 .9 1.1]),diag([.7i .9 .8i .6])};
for ue=1:2
    receiveCfg{ue}=sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,ue,ue,1);
    refs{ue}=sixgr.phy.srs.buildSRSConfigFromScenario(receiveCfg{ue});
    carrier=refs{ue}.ToolboxCarrier; carrier.NSlot=4;
    grids{ue}=nrResourceGrid(carrier,refs{ue}.NumSRSPorts);
    grids{ue}(nrSRSIndices(carrier,refs{ue}.ToolboxSRS))=nrSRS(carrier,refs{ue}.ToolboxSRS);
    assert(any(grids{ue}~=0,'all'),'The configured native SRS occasion must execute.');
end
occupied=cellfun(@(g)any(g~=0,3),grids,'UniformOutput',false);
assert(~any(occupied{1}&occupied{2},'all'), ...
    'Declared comb separation must remain disjoint after four-port expansion.');
K=size(grids{1},1); L=size(grids{1},2); ports=size(grids{1},3);
received=complex(zeros(K,L,ports));
for ue=1:2
    received=received+reshape(reshape(grids{ue},[],ports)*channels{ue},K,L,ports);
end
variance=.01; % Explicit 20-dB unit-pilot/grid-noise component experiment.
stream=RandStream('mt19937ar','Seed',5101010);
received=received+sqrt(variance/2)*(randn(stream,K,L,ports)+1i*randn(stream,K,L,ports));
waveform=nrOFDMModulate(carrier,received,'Windowing',0);
for ue=1:2
    [rx,info]=sixgr.phy.ul.SRS_Rx(waveform,receiveCfg{ue}, ...
        'Carrier',carrier,'SRS',refs{ue}.ToolboxSRS);
    expectedH=repmat(reshape(channels{ue}.',1,1,ports,ports),K,L,1,1);
    score=sixgr.phy.srs.pilotChannelNMSE(rx.Hest,expectedH,rx.SRSIndices);
    noiseError=10*log10(rx.NoiseVar/variance);
    assert(isfinite(score.dB) && score.dB<-15 && ...
        isfinite(noiseError) && abs(noiseError)<3, ...
        'test:TwoUESRSReceiver','UE %d: NMSE=%g dB, noise error=%g dB.',ue,score.dB,noiseError);
    assert(~info.ChannelEstimation.PrimaryEstimatorFallbackUsed, ...
        'The exact resource receiver must not rely on fallback estimation.');
    fprintf('TWO_UE_SRS_RECEIVED ue=%d ports=%d NMSE_dB=%g noise_error_dB=%g\n', ...
        ue,ports,score.dB,noiseError);
end
ok=true;
disp('TWO_UE_SRS_CADENCE_PASS: exact TDD calendar and composite receiver; not an attach campaign.');
end
