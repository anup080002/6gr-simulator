function ok=testInstalledTXRadiationBinding()
% Component contract: original installed native arrays, real reciprocal
% native installation and real RF processing of DECLARED sample sequences.
% No scheduled waveform, shared-runtime radiation publication, feed-power
% calibration, propagation result or hardware qualification is claimed.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
multi=sixgr.truth.resolveMultiUserSpec(cfg);
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempdir,multi,struct(),0);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
bs=dl.lls6g.userContext.RuntimeServingBSAntenna;
bm=dl.lls6g.userContext.RuntimeServingBSAntennaMeta;
ue=ul.lls6g.userContext.RuntimeUEAntenna;
um=ul.lls6g.userContext.RuntimeUEAntennaMeta;
nBS=bs.NumElements; nUE=ue.NumElements;
assert(nBS~=nUE,'The reciprocal getter regression requires unequal original endpoint dimensions.');
native=nrOFDMInfo(sixgr.phy.grid.makeCarrier(dl)); fs=double(native.SampleRate);
epoch=double(cfg.rf.configurationEpoch); policy=struct('AzimuthCount',12,'ElevationCount',6);
tx=sixgr.rf.runtime.RFImpairmentStream(dl,'tx','DL',fs,nBS,0,epoch,false);
bsReference=dl.rf.bsPowerReference;
binding=sixgr.rf.InstalledTXRadiationBinding.freeze(bs,bm,tx,"gnb_1",policy,bsReference);
a=binding.capsule(); field=binding.fieldEvidence();
assert(a.PhysicalChainCount==nBS&&a.Geometry.CarrierFrequencyHz==bs.Fc_Hz&& ...
    a.DeclaredRFReference.RFType=="1-O"&&~a.ExecutionVerified&& ...
    ~a.AcceptedFeedPowerQualified&&~a.HardwareConformanceVerified&& ...
    ~a.PowerRenormalizationApplied&&a.CoordinateFrame=="installed_array_local_coordinates");
again=sixgr.rf.InstalledTXRadiationBinding.freeze(bs,orderfields(bm),tx,"gnb_1",orderfields(policy),bsReference);
assert(isequaln(a,again.capsule()),'Original value metadata must have stable field-order-independent identity.');
assert(field.FrequencyHz==bs.Fc_Hz&&size(field.H,1)==nBS&& ...
    a.FieldIdentity.HSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(field.H));
% Caller copies cannot mutate the retained native field or capsule.
copy=a; copy.Geometry.ElementPositions_m(1,1)=999;
fieldCopy=field; fieldCopy.H(1,1)=999;
assert(isequaln(a,binding.capsule())&&isequaln(field,binding.fieldEvidence()));

% Install the actual runtime arrays through the production native factory.
% No channel samples are executed here, so direction swaps have no outgoing
% FIR history to discard. Later tests cover original RF intervals separately.
state=sixgr.channel.ChannelFactory.createRuntimeChannelState(dl,'DL','UEIndex',1,'ServingCell',1);
info=struct('OFDM',struct('SampleRate',fs));
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,dl, ...
    complex(zeros(1,nBS)),info,'NumTxAnt',nBS,'NumRxAnt',nUE, ...
    'TransmitAntennaRuntime',bs,'ReceiveAntennaRuntime',ue, ...
    'TransmitAntennaMeta',bm,'ReceiveAntennaMeta',um);
assert(state.Materialized&&isa(state.Obj,'nrCDLChannel')&& ...
    state.CurrentSampleIndex==0&&~state.Obj.TransmitAndReceiveSwapped);
installed=binding.validateChannel(state,"gnb_1");
assert(installed.InstallationSHA256==a.InstallationSHA256&& ...
    installed.NativeGetter=="current_TransmitAntennaArray_no_second_swap"&& ...
    ~installed.WaveformExecutionVerified);
% Equivalent native clones are legal; a global handle equality is not an
% array-definition check. The original RF owner, by contrast, is bound below.
cloned=state; cloned.Obj=clone(state.Obj);
assert(isequaln(installed,binding.validateChannel(cloned,"gnb_1")));

utx=sixgr.rf.runtime.RFImpairmentStream(ul,'tx','UL',fs,nUE,0,epoch,false);
% The selected YAML does not declare a UE RF reference. This component
% explicitly declares ONLY an internal model boundary, not a UE RF type.
ueReference=struct('RFType',"undeclared_component_reference", ...
    'RequirementBoundary',"internal_post_TX_RF_model_only", ...
    'Scope',"declared_component_policy_not_hardware_or_standardized_reference");
ub=sixgr.rf.InstalledTXRadiationBinding.freeze(ue,um,utx,"ue_1",policy,ueReference);
state.Direction='UL';
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,ul,complex(zeros(1,nUE)),info);
assert(state.Obj.TransmitAndReceiveSwapped&&state.NumTxAnt==nUE&&state.NumRxAnt==nBS&& ...
    getNumElements(state.Obj.TransmitAntennaArray)==nUE&& ...
    getNumElements(state.Obj.ReceiveAntennaArray)==nBS);
ucheck=ub.validateChannel(state,"ue_1");
assert(ucheck.CarrierFrequencyHz==ue.Fc_Hz&&ucheck.Direction=="UL");
reject(@()binding.validateChannel(state,"gnb_1"),'RF:TXRadiationChannelInstallation');
state.Direction='DL';
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,dl,complex(zeros(1,nBS)),info);
assert(~state.Obj.TransmitAndReceiveSwapped&&state.NumTxAnt==nBS&&state.NumRxAnt==nUE);
assert(isequaln(installed,binding.validateChannel(state,"gnb_1")));

% Cloning preserves the native lock state. Release only these disposable
% negative-fixture clones, never the original installed channel/RF owner.
bad=state; bad.Obj=clone(state.Obj); release(bad.Obj);
array=clone(bad.Obj.TransmitAntennaArray); release(array);
array.Spacing=array.Spacing.*[1.01 1 1 1]; bad.Obj.TransmitAntennaArray=array;
reject(@()binding.validateChannel(bad,"gnb_1"),'RF:TXRadiationChannelInstallation');
bad=state; bad.Obj=clone(state.Obj); release(bad.Obj);
array=clone(bad.Obj.TransmitAntennaArray); release(array);
array.ElementSet=array.ElementSet(end:-1:1); bad.Obj.TransmitAntennaArray=array;
reject(@()binding.validateChannel(bad,"gnb_1"),'RF:TXRadiationChannelInstallation');
bad=state; bad.Obj=clone(state.Obj); release(bad.Obj); bad.Obj.CarrierFrequency=bs.Fc_Hz+1;
reject(@()binding.validateChannel(bad,"gnb_1"),'RF:TXRadiationChannelInstallation');
bad=state; bad.Obj=clone(state.Obj); release(bad.Obj);
bad.Obj.TransmitArrayOrientation=bad.Obj.TransmitArrayOrientation+[1;0;0];
reject(@()binding.validateChannel(bad,"gnb_1"),'RF:TXRadiationChannelInstallation');
bad=state; bad.SampleRate_Hz=fs*2;
reject(@()binding.validateChannel(bad,"gnb_1"),'RF:TXRadiationChannelInstallation');
reject(@()binding.validateChannel(state,"gnb_2"),'RF:TXRadiationEndpointMismatch');

bad=bs; bad.ElementPositions_m(1,1)=bad.ElementPositions_m(1,1)+1;
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bad,bm,tx,"gnb_1",policy,bsReference),'RF:TXRadiationInstallation');
bad=bs; different=find(bad.PolarizationIndexByElement~=bad.PolarizationIndexByElement(1),1);
assert(~isempty(different)); bad.PolarizationIndexByElement([1 different])=bad.PolarizationIndexByElement([different 1]);
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bad,bm,tx,"gnb_1",policy,bsReference),'RF:TXRadiationInstallation');
bad=bs; bad.Fc_Hz=bad.Fc_Hz+1;
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bad,bm,tx,"gnb_1",policy,bsReference),'RF:TXRadiationInstallation');
badMeta=bm; badMeta.BoresightSlant_deg=badMeta.BoresightSlant_deg+1;
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bs,badMeta,tx,"gnb_1",policy,bsReference),'RF:TXRadiationInstallation');
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bs,bm,tx,"gnb_1",rmfield(policy,'AzimuthCount'),bsReference),'RF:TXRadiationInstallation');
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bs,bm,tx,"gnb_1",policy,struct()),'RF:TXRadiationInstallation');

before=rng;
% Coherent vs sign-orthogonal declared physical input sequences. Compare
% their REAL post-RF covariances/patterns, not an ideal pre-RF covariance.
x=complex(zeros(64,nBS)); x(:,1:2)=1;
chunk=sixgr.phy.waveform.WaveformChunk(x,0);
actual=actualRF(tx,chunk,epoch);
[receipt,model]=binding.bindExecution(chunk,actual,tx,"gnb_1");
assert(receipt.OriginalRFIntervalVerified&&receipt.StartSample==0&& ...
    receipt.EndSampleExclusive==size(x,1)&&receipt.SampleRateHz==fs&& ...
    receipt.PhysicalConfigurationEpoch==epoch&& ...
    receipt.RFInputWaveformSHA256==string(actual.Replay.RFInputWaveformSHA256)&& ...
    receipt.RFOutputWaveformSHA256==string(actual.Replay.RFOutputWaveformSHA256)&& ...
    receipt.SpatialMatrixSHA256==actual.Replay.TXSpatialPower.MatrixSHA256&& ...
    ~receipt.InternalSamplePowerIsAcceptedFeedPower&&~receipt.AcceptedFeedPowerQualified&& ...
    ~receipt.NativeChannelExecutionQualified&&~receipt.ProductionOwnerIntegrationVerified&& ...
    ~receipt.HardwareConformanceVerified&&~receipt.PowerRenormalizationApplied&& ...
    ~model.FeedPowerConservationQualified&&~model.GridPeakIsContinuousPeak);
assertNativePattern(actual.Waveform,bs,field,model);
other=sixgr.rf.runtime.RFImpairmentStream(dl,'tx','DL',fs,nBS,0,epoch,false);
otherBinding=sixgr.rf.InstalledTXRadiationBinding.freeze(bs,bm,other,"gnb_1",policy,bsReference);
z=x; z(2:2:end,2)=-1;
zchunk=sixgr.phy.waveform.WaveformChunk(z,0); alternate=actualRF(other,zchunk,epoch);
[otherReceipt,otherModel]=otherBinding.bindExecution(zchunk,alternate,other,"gnb_1");
assertNativePattern(alternate.Waveform,bs,field,otherModel);
r=actual.Replay.TXSpatialPower.SecondMoment; q=alternate.Replay.TXSpatialPower.SecondMoment;
assert(abs(r(1,2))>abs(q(1,2))&&receipt.SpatialMatrixSHA256~=otherReceipt.SpatialMatrixSHA256&& ...
    norm(model.ModelDirectionalEIRP_mW-otherModel.ModelDirectionalEIRP_mW)>0, ...
    'Keep actual coherent cross terms; a trace-only replacement cannot pass.');
diagonal=actual.Replay.TXSpatialPower; diagonal.SecondMoment=diag(diag(r));
diagonal.MatrixSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(diagonal.SecondMoment);
bad=actual; bad.Replay.TXSpatialPower=diagonal;
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationCovarianceMismatch');
reject(@()binding.bindExecution(chunk,actual,other,"gnb_1"),'RF:TXRadiationOwnerMismatch');
reject(@()binding.bindExecution(chunk,actual,tx,"gnb_2"),'RF:TXRadiationEndpointMismatch');
bad=actual; bad.Replay.RFConfigurationEpoch=epoch+1;
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationExecution');
bad=actual; bad.Replay.RFStreamEndSampleExclusive=65;
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationExecution');
bad=actual; bad.Replay.RFInputWaveformSHA256=repmat('0',1,64);
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationWaveformMismatch');
bad=actual; bad.Replay.RFOutputWaveformSHA256=repmat('0',1,64);
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationWaveformMismatch');
bad=actual; bad.Replay.TXSpatialPower.MatrixSHA256=repmat('0',1,64);
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationCovarianceMismatch');
bad=actual; bad.Replay.WaveformAmplitudeUnit="normalized_complex_baseband";
reject(@()binding.bindExecution(chunk,bad,tx,"gnb_1"),'RF:TXRadiationExecution');
changed=sixgr.phy.waveform.WaveformChunk(x(:,[2 1 3:nBS])*2,0);
reject(@()binding.bindExecution(changed,actual,tx,"gnb_1"),'RF:TXRadiationWaveformMismatch');
shifted=sixgr.phy.waveform.WaveformChunk(x,1);
reject(@()binding.bindExecution(shifted,actual,tx,"gnb_1"),'RF:TXRadiationExecution');
reject(@()sixgr.rf.InstalledTXRadiationBinding.freeze(bs,bm,tx,"gnb_1",policy,bsReference),'RF:TXRadiationInstallation');
% Stale intervals cannot be rebound after the original RF owner advances.
next=sixgr.phy.waveform.WaveformChunk(complex(zeros(8,nBS)),64);
actualNext=actualRF(tx,next,epoch);
nextReceipt=binding.bindExecution(next,actualNext,tx,"gnb_1");
assert(nextReceipt.StartSample==64&&nextReceipt.EndSampleExclusive==72);
reject(@()binding.bindExecution(chunk,actual,tx,"gnb_1"),'RF:TXRadiationExecution');
assert(isequal(rng,before),'Strict binding and native radiation must not mutate global RNG.');
fprintf('INSTALLED_TX_RADIATION_BINDING_PASS native_reciprocal_installation=1 actual_RF_intervals=3 shared_radiation_integration=0 accepted_feed_qualification=0 hardware_qualification=0\n');
ok=true;
end

function actual=actualRF(stream,chunk,epoch)
% Original RF call, followed by the same measurement producers currently
% used in SharedWaveformPhysicalRuntime.process. This is not owner wiring.
actual=stream.apply(chunk,epoch);
power=sixgr.rf.PowerContext(stream.Configuration,stream.Chain.Direction);
assert(stream.Configuration.rf.txSpatialPowerEnabled);
actual.Replay.WaveformAmplitudeUnit=string(power.WaveformAmplitudeUnit);
actual.Replay.TXSpatialPowerEnabled=true;
actual.Replay.TXSpatialPower=sixgr.rf.measurePhysicalTXSpatialPower(actual.Waveform);
end

function assertNativePattern(samples,array,field,model)
% Independent native radiation of the actual post-RF samples; no normalization
% to trace(R) or to a preferred TRP/internal-power ratio is allowed.
radiator=phased.Radiator('Sensor',clone(array.ArrayObj),'OperatingFrequency',array.Fc_Hz, ...
    'Polarization','Combined','SensorGainMeasure','dB');
native=radiator(samples,field.AzimuthElevation_deg,eye(3));
power=zeros(1,numel(native));
for k=1:numel(native)
    power(k)=mean(abs(native(k).X).^2+abs(native(k).Y).^2+abs(native(k).Z).^2);
end
scale=max(max(power),realmin);
assert(max(abs(power-model.ModelDirectionalEIRP_mW))<1e-10*scale);
expected=power*field.SolidAngle_sr/(4*pi);
assert(abs(model.ModelTRP_mW-expected)<1e-10*scale&&~model.PowerRenormalizationApplied);
end

function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s got %s',id,cause.identifier); return; end
error('test:TXRadiationExpectedError','Expected %s.',id);
end
