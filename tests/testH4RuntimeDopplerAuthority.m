function ok = testH4RuntimeDopplerAuthority()
% Actual H4 builder/user binding and native fading objects; no BLER claim.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
folder = tempname; mkdir(folder);
cleanup = onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(s,folder);
maximum = cfg.channel.dopplerConfigured_Hz;
multi = struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx=1;
[~,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,"DL");
% Transverse motion: zero geometric radial shift, nonzero fading spread.
state.LargeScaleState.UEVelocity_mps(1,:)=[0 3/3.6 0];
state.LargeScaleState.Doppler_Hz(1,1)=0;
state.LargeScaleState.SignedDoppler_Hz(1,1)=0;
for direction=["DL","UL"]
    bound=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,direction);
    assert(bound.channel.doppler_Hz==maximum && bound.channel.dopplerHz==maximum && ...
        bound.channel.maxDoppler_Hz==maximum && bound.channel.maxDopplerHz==maximum && ...
        bound.channel.fading.maxDoppler_Hz==maximum);
    assert(bound.channel.runtimeProjectedRadialDoppler_Hz==0);
end
bound=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,"DL");
% Materialize and filter through the real 64-by-4 H4 channel at its real Fs.
info=struct('OFDM',struct('SampleRate',122.88e6));
key=sixgr.channel.ChannelFactory.runtimeChannelKey(bound,"DL",'UEIndex',1,'ServingCell',1);
ch=sixgr.channel.ChannelFactory.createRuntimeChannelState(bound,"DL",'LinkKey',key);
ch=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(ch,bound, ...
    complex(zeros(32,64)),info,'NumTxAnt',64,'NumRxAnt',4);
assert(isa(ch.Obj,'nrCDLChannel') && max(ch.Obj.MaximumDopplerShift)==maximum);
assert(isequal(ch.Obj.UTDirectionOfTravel,[90;90]));
state.RuntimeChannelStates=ch;
row=sixgr.truth.bindRuntimeDopplerEvidence(struct(),state,1,1);
assert(row.AppliedDopplerHz==maximum && row.ExpectedDopplerHz==maximum && ...
    row.ProjectedRadialDopplerHz==0 && row.AppliedDopplerSource=="nrCDLChannel.MaximumDopplerShift");
[y,~,ch]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(ch,complex(ones(32,64)));
assert(size(y,2)==4 && all(isfinite(y(:))));
ch.Direction='UL';
ch=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(ch,bound, ...
    complex(zeros(32,4)),info,'NumTxAnt',4,'NumRxAnt',64);
assert(ch.Obj.TransmitAndReceiveSwapped && max(ch.Obj.MaximumDopplerShift)==maximum);
% Swapping the native channel reverses mobility endpoints, not its maximum.
assert(isequal(ch.Obj.UTDirectionOfTravel(:,end),[90;90]));
[y,~,ch]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(ch,complex(ones(32,4)));
assert(size(y,2)==64 && all(isfinite(y(:))));

derived=cfg; derived.channel.dopplerSourceMode='derive_from_ue_speed';
bound=sixgr.truth.CoupledTruthRuntime.applyUserContext(derived,state,1,"DL");
expected=(3/3.6)*4e9/299792458;
assert(abs(bound.channel.doppler_Hz-expected)<1e-12 && bound.channel.doppler_Hz>0);
state.LargeScaleState.UEVelocity_mps(1,:)=[0 0 0];
bound=sixgr.truth.CoupledTruthRuntime.applyUserContext(derived,state,1,"DL");
assert(bound.channel.doppler_Hz==0);
bound=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,"DL");
assert(bound.channel.doppler_Hz==maximum,'Configured experiment maximum must not follow geometry.');
bad=cfg; bad.channel.dopplerConfigured_Hz=-1;
didReject=false;
try, sixgr.channel.bindRuntimeDoppler(bad); catch, didReject=true; end
assert(didReject,'Invalid configured maximum must not be clamped to zero.');

% TDL also consumes the maximum rather than the projected ray shift.
tdl=cfg; tdl.channel.model='TDL-A'; tdl.channel.tdlProfile='TDL-A';
tdl.channel=rmfield(tdl.channel,'cdlProfile');
tdl.channel.delayProfile='TDL-A'; tdl.channel.fading.model='TDL';
tdl.channel.fading.profile='TDL-A';
native=sixgr.channel.ChannelFactory.create(tdl,'SampleRate',122.88e6,'NumTxAnt',2,'NumRxAnt',2);
assert(native.Object.MaximumDopplerShift==maximum && native.Meta.MaximumDopplerShift_Hz==maximum);
ok=true; fprintf('H4_RUNTIME_DOPPLER_AUTHORITY_PASS\n');
end
