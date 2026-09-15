function ok=testReceivedDLQCLAuthority()
% Actual saved DCI and data; explicit QCL source fixture, not received TRS proof.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
saved=load(fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_02','attempt_2.mat'));
a=saved.a;
% Exercise the real runtime identity producer. Hand-setting the Index field
% here previously hid the production applyUserContext integration gap.
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(installed,tempname,multi,struct(),a.DataAbsoluteSlot+1);
runtime.CurrentSlot=a.DataAbsoluteSlot+1;
[cfg,runtime]=sixgr.truth.CoupledTruthRuntime.applyUserContext(installed,runtime,1,'DL');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,a.DataAbsoluteSlot+1);
assert(isfield(cfg.lls6g.userContext,'RuntimeServingCellIndex') && ...
    cfg.lls6g.userContext.RuntimeServingCellIndex==runtime.CurrentServingIdx(1), ...
    'testReceivedDLQCLAuthority:MissingRuntimeServingCellIndex', ...
    'The actual runtime binder must supply its serving-cell index; the receiver test must not manufacture it.');
stale=installed; stale.lls6g.userContext.RuntimeServingCellIndex=999;
for direction=["DL","UL"]
    rebound=sixgr.truth.CoupledTruthRuntime.applyUserContext(stale,runtime,1,direction);
    assert(rebound.lls6g.userContext.RuntimeServingCellIndex==runtime.CurrentServingIdx(1), ...
        'A stale user-context cell index must not survive current runtime binding.');
end
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=nrOFDMInfo(carrier).SampleRate;
nominal=sixgr.phy.frame.slotStartSample(carrier,a.DataAbsoluteSlot,fs);
context=sixgr.phy.pdcch.validateConnectedAssignment(cfg,a);
source=struct('UEIndex',1,'ServingCellIndex',double(runtime.CurrentServingIdx(1)), ...
    'RRCServingCellIndex',double(context.Data.ScheduledServingCell), ...
    'SourceResourceID',100,'ConfigurationEpoch',1,'SourceSlot0',a.DataAbsoluteSlot-2, ...
    'AvailableAtSample',nominal-1,'SampleRateHz',fs,'TimingPhaseSamples',43, ...
    'Source',"received_nzp_csi_rs_trs_timing_estimator");
% The values above are a declared source-boundary test fixture. They must
% not be exported as measurements from a real TRS reception.
cfg.lls6g.userContext.QCLTimingReference=source;
observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    nominal,nominal+size(saved.delayed,1),fs,size(saved.delayed,2));
[window,evidence]=sixgr.phy.rx.applyQCLTimingTransfer(cfg,a,observation,nominal,[0 60],1);
assert(isequal(window,[39 47]) && evidence.QCLTimingPriorSamples==43 && ...
    evidence.TCIStateID==17 && evidence.TCICodepoint==0);
[rx,decision]=saved.before.receive(cfg,a,saved.delayed,'TimingSearchWindowSamples',window);
assert(decision.ACK && rx.CRCPass && isequal(rx.TransportBlock,saved.bits) && ...
    rx.TimingOffset==43 && isequal(rx.ReceiveTiming.SearchWindowSamples,window) && ...
    ~rx.ReceiveTiming.OracleTimingUsed);
bad=a; bad.TCICodepoint=17;
reject(@()sixgr.phy.rx.applyQCLTimingTransfer(cfg,bad,observation,nominal,[0 60],1), ...
    'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
badCfg=cfg; badCfg.lls6g.runtime.AbsoluteSlotIndex0=a.DataAbsoluteSlot+1;
reject(@()sixgr.phy.rx.applyQCLTimingTransfer(badCfg,a,observation,nominal,[0 60],1), ...
    'sixgr:qcl:ReceivedAssignmentClockMismatch');
for field=["UEIndex","ServingCellIndex","RRCServingCellIndex","SampleRateHz"]
    badCfg=cfg; badCfg.lls6g.userContext.QCLTimingReference.(field)=source.(field)+1;
    reject(@()sixgr.phy.rx.applyQCLTimingTransfer(badCfg,a,observation,nominal,[0 60],1), ...
        'sixgr:qcl:ReferenceIdentityMismatch');
end
badCfg=cfg; badCfg.lls6g.userContext.QCLTimingReference.AvailableAtSample=nominal+1;
reject(@()sixgr.phy.rx.applyQCLTimingTransfer(badCfg,a,observation,nominal,[0 60],1), ...
    'sixgr:qcl:InactiveOrStaleReference');
legacy=struct('UEIndex',1,'ServingCell',1,'ReceivedTCICodepoint',0, ...
    'ReceivedTCIConfigurationEpoch',1,'DCICrcPass',true,'PDCCHPayloadMatch',true, ...
    'PDCCHCausalGrantDecodeOk',true,'PDCCHGrantBindingOk',true);
reject(@()sixgr.phy.rx.applyQCLTimingTransfer(cfg,legacy,observation,nominal,[0 60]), ...
    'sixgr:qcl:MissingReceivedTCI');
fprintf('RECEIVED_DL_QCL_AUTHORITY_PASS bits=%d delay=%g window=[%g %g] guards=8 source=explicit_boundary_fixture\n', ...
    numel(rx.TransportBlock),rx.TimingOffset,window);
ok=true;
end

function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
