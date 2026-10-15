function ok=testCoupledRAObservationIdentity()
% Production physical completion -> RA RF publisher. One silent monitoring
% slot is deliberately not evidence of PRACH detection or UE attachment.
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_pucch_gnb_receive_only_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,root); cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
state.CurrentSNR_dB=cfg.channel.snr_dB;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
carrier=sixgr.phy.grid.makeCarrier(cfg);
mu=log2(double(carrier.SubcarrierSpacing)/15);
finish=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(1,0,mu);
ra=struct('RunId',"physical_completion_identity_fixture",'UEId',1,'AttemptId',1, ...
    'RARMonitoringWindow',struct('ExpiryTicksExclusive',finish.Ticks, ...
    'MonitoringSlots',0,'Numerology',mu,'ClockOffsetTicks',int64(0)));
owner.armRARWindow(1,ra);
expected=string(owner.Pending.ID);
state.IdentityTestRA=ra; state.IdentityTestRF=table();
[state,completed]=owner.advanceSlot(state,cfg,@localReceived);
assert(numel(completed)==2 && all(strlength(string({completed.ID}))>0) && ...
    numel(unique(string({completed.ID})))==2);
assert(isequal(string({completed.Kind}),["RAR","RARExpiry"]), ...
    'Complete receiver evidence before the expiry at the same physical boundary.');
assert(completed(1).ID==expected && height(state.IdentityTestRF)==1 && ...
    state.IdentityTestRF.ObservationID==expected);
assert(state.IdentityTestRF.ResultAvailableAtSample==owner.Events.NextSampleIndex && ...
    state.IdentityTestRF.StageName=="RARMonitoring");
assert(isempty(owner.Pending));
[~,empty]=owner.drainDataReceiveTail(state,cfg);
assert(isempty(empty) && isequal(fieldnames(empty),fieldnames(completed)), ...
    'Empty receive-tail completion schema must retain the same identity contract.');
ok=true; fprintf('COUPLED_RA_OBSERVATION_IDENTITY_PASS actual_receiver_callback=1 expiry_order=1 identity_retained=1\n');
end

function state=localReceived(state,items)
for item=items
    if item.Kind=="RAR"
        row=sixgr.truth.buildRAReceiverRFObservation(item,state.IdentityTestRA,1, ...
            state.CurrentSNR_dB,state.SharedWaveformStream.Events.NextSampleIndex);
        state.IdentityTestRF=[state.IdentityTestRF;row];
    end
end
end
