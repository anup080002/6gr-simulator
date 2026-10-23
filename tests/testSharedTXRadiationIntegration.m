function ok=testSharedTXRadiationIntegration()
% Actual shared RF/channel intervals on DECLARED IQ, not decoded PHY/access.
% Two independent owners prove recording leaves samples/clock/RNG unchanged.
% Local native-field radiation is a model, not accepted-feed/hardware power.
setup6GRSimToolkit('Verbose',false);
auditParent=fullfile(pwd,'logs','shared_tx_radiation_integration');
if ~isfolder(auditParent), mkdir(auditParent); end
auditRoot=tempname(auditParent); mkdir(auditRoot);
fprintf('SHARED_TX_RADIATION_AUDIT %s\n',auditRoot);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
originalDeclaration=source.Data; declared=originalDeclaration;
assert(declared.power_and_rf_frontend.modeled_radiated_power.enabled);
% Explicit component quadrature for a bounded execution, not a peak or
% convergence qualification. Original carrier/geometry/channel/RF stay intact.
declared.power_and_rf_frontend.modeled_radiated_power.azimuth_count=12;
declared.power_and_rf_frontend.modeled_radiated_power.elevation_count=6;
sixgr.lls6g.config.validateScenarioConfig(declared,'Kind',source.Kind, ...
    'AllowPartial',false,'Context','declared shared-radiation component quadrature');
component=sixgr.lls6g.config.ScenarioConfig(declared, ...
    'SourceFiles',source.SourceFiles,'ConfigPath',source.ConfigPath, ...
    'ConfigHash',sixgr.lls6g.config.hashResolvedScenario(declared),'Kind',source.Kind);
assert(~isequal(component.ConfigHash,source.ConfigHash)&& ...
    isequaln(source.Data,originalDeclaration), ...
    'The declared component override must not mutate the immutable source scenario.');
cfg=sixgr.lls6g.buildInternalConfig(component,tempdir);
assert(cfg.rf.modeledRadiatedPower.Enabled&&cfg.rf.txSpatialPowerEnabled);
policyChecks(component.Data.power_and_rf_frontend.modeled_radiated_power);
multi=sixgr.truth.resolveMultiUserSpec(cfg);
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempdir,multi,struct(),0);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
window=sixgr.truth.resolveTRSObservationWindow(dl,1);
slot=window.AbsoluteSlotNumbers(1)+1;
window=sixgr.truth.resolveTRSObservationWindow(dl,slot);
assert(window.ObservationStarts&&sixgr.truth.isActiveTRSOccasion(dl,slot));
p=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',slot);
tx=p.Tx; tx.Waveform=p.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(p.ReceiverConfig,tx,p.TxInfo);
channel=truth.RuntimeChannelState;
assert(isa(channel.Obj,'nrCDLChannel')&&channel.NumTxAnt==64&&channel.NumRxAnt==4&& ...
    channel.CurrentSampleIndex==0&&channel.Meta.RuntimeTDDReciprocityExact);
fs=channel.SampleRate_Hz; epoch=cfg.rf.configurationEpoch;
disabledDL=dl; disabledUL=ul;
disabledDL.rf.modeledRadiatedPower=struct('Enabled',false);
disabledUL.rf.modeledRadiatedPower=struct('Enabled',false);
before=rng;
original=makeOwner(dl,ul,channel);
plain=makeOwner(disabledDL,disabledUL,sixgr.channel.ChannelFactory.forkRuntimeChannelState(channel));
retainOwners('registered');
assert(isequal(before,rng),'Registration/field sampling must not consume global random draws.');
initial=original.readRFExecutionLedger(); library=initial.TXRadiationLibrary;
assert(numel(library)==2&&isempty(initial.TXRadiationIntervals)&& ...
    ~initial.ModeledRadiationCompleteFromOrigin);
assert(library(1).Installation.PhysicalChainCount==64&& ...
    library(2).Installation.PhysicalChainCount==4&& ...
    library(2).Installation.DeclaredRFReference.RFType=="undeclared_UE_RF_type_model_only");
original.validateTransmitterInstallation('gnb',dl,'DL',64);
original.validateTransmitterInstallation('ue',ul,'UL',4);
bad=dl; bad.rf.modeledRadiatedPower.Quadrature.AzimuthCount=24;
reject(@()original.validateTransmitterInstallation('gnb',bad,'DL',64),'RF:TXRadiationInstallationChanged');
bad=dl; bad.rf.bsPowerReference.Scope='different_declared_scope';
reject(@()original.validateTransmitterInstallation('gnb',bad,'DL',64),'RF:TXRadiationInstallationChanged');
reject(@()original.validateTransmitterInstallation('gnb',disabledDL,'DL',64),'RF:TXRadiationInstallationChanged');
bad=dl; bad.lls6g.userContext.RuntimeServingBSAntenna.ElementPositions_m(1,1)=42;
reject(@()original.validateTransmitterInstallation('gnb',bad,'DL',64),'RF:TXRadiationInstallation');
unchanged=original.readRFExecutionLedger();
assert(isequaln(library,unchanged.TXRadiationLibrary));

executions=cell(5,1);
runInterval(37,'DL',false,1);
runInterval(tailSamples(dl,channel,'DL'),'DL',true,2);
retainOwners('before_retarget_UL');
original.retargetTDDLink('serving','ue','gnb_rx',ul);
retainOwners('after_enabled_retarget_UL');
plain.retargetTDDLink('serving','ue','gnb_rx',disabledUL);
retainOwners('after_both_retarget_UL');
runInterval(41,'UL',false,3);
runInterval(tailSamples(ul,channel,'UL'),'UL',true,4);
retainOwners('before_retarget_DL');
original.retargetTDDLink('serving','gnb','ue_rx',dl);
retainOwners('after_enabled_retarget_DL');
plain.retargetTDDLink('serving','gnb','ue_rx',disabledDL);
retainOwners('after_both_retarget_DL');
runInterval(23,'DL',false,5);
assert(isequal(before,rng),'Recording must not consume global RNG state.');
e=original.readRFExecutionLedger(); q=plain.readRFExecutionLedger();
assert(e.CompleteFromOrigin&&e.TXSpatialPowerCompleteFromOrigin&& ...
    e.ModeledRadiationCompleteFromOrigin&&height(e.TXRadiationIntervals)==10&& ...
    numel(e.TXRadiationNativeBindings)==3&&isequaln(library,e.TXRadiationLibrary));
assert(isequaln(e.Intervals,q.Intervals)&&isequaln(e.ChainPowerIntervals,q.ChainPowerIntervals)&& ...
    isequaln(e.TXSpatialPowerIntervals,q.TXSpatialPowerIntervals)&& ...
    isempty(q.TXRadiationLibrary)&&isempty(q.TXRadiationIntervals)&&~q.ModeledRadiationCompleteFromOrigin);
rows=e.TXRadiationIntervals;
assert(all(rows.ModelIntegratedRadiationVerified)&& ...
    ~any(rows.AcceptedFeedPowerQualified|rows.HardwareConformanceVerified|rows.PowerRenormalizationApplied)&& ...
    nnz(rows.NativeChannelInstallationMatched)==5);
assert(all(rows.CoordinateFrame=="installed_array_local_coordinates")&& ...
    all(rows.FrequencyScope=="frequency_flat_installed_carrier_field_model"));
atomicChecks(e,executions);
publicationChecks(cfg,e);
fprintf('SHARED_TX_RADIATION_INTEGRATION_PASS actual_RF_channel_intervals=5 TX_intervals=10 native_retargets=2 unchanged_samples=1 decoded_PHY=0 hardware_feed_qualified=0\n');
ok=true;

    function owner=makeOwner(down,up,state)
        owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
        owner.addTransmitter('gnb',down,'DL',64,false);
        owner.addTransmitter('ue',up,'UL',4,false);
        owner.addReceiver('ue_rx',down,'DL',4,false);
        owner.addReceiver('gnb_rx',up,'UL',64,false);
        owner.addLink('serving','gnb','ue_rx',state,down);
        owner.enableRFExecutionLedger();
    end
    function runInterval(n,direction,idle,index)
        first=original.NextSampleIndex; stop=first+n;
        assert(plain.NextSampleIndex==first);
        x=complex(zeros(n,64)); u=complex(zeros(n,4));
        if ~idle
            if string(direction)=="DL", x=reshape(.01*exp(1i*(1:n*64)/19),n,64);
            else, u=reshape(.01*exp(1i*(1:n*4)/23),n,4); end
        end
        inputs(1)=struct('ID',"gnb",'Chunk',sixgr.phy.waveform.WaveformChunk(x,first));
        inputs(2)=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk(u,first));
        prefix=sprintf('interval_%02d_%s',index,direction);
        stateBefore=retainOwners([prefix '_before_enabled']);
        rngBeforeEnabled=rng;
        [actual,execution]=original.process(inputs,first,stop,[]);
        rngAfterEnabled=rng;
        stateBetween=retainOwners([prefix '_before_plain']);
        [reference,plainExecution]=plain.process(inputs,first,stop,[]);
        rngAfterPlain=rng;
        stateAfter=retainOwners([prefix '_after_both']);
        % Persist the ORIGINAL bounded operands before any comparison can
        % abort. No extra RF/channel call, reset, clone or toleranced check.
        interval=struct('Index',index,'Direction',string(direction),'Idle',idle, ...
            'StartSample',first,'EndSampleExclusive',stop,'Inputs',inputs, ...
            'Actual',actual,'Reference',reference,'Execution',execution, ...
            'PlainExecution',plainExecution,'RNGBeforeEnabled',rngBeforeEnabled, ...
            'RNGAfterEnabled',rngAfterEnabled,'RNGAfterPlain',rngAfterPlain, ...
            'StateBeforeFile',stateBefore,'StateBetweenFile',stateBetween, ...
            'StateAfterFile',stateAfter);
        save(fullfile(auditRoot,[prefix '_original_operands.mat']),'interval','-v7.3');
        assert(isequal(string({actual.ID}),string({reference.ID})));
        for k=1:numel(actual)
            if ~isequaln(actual(k).Chunk.Samples,reference(k).Chunk.Samples)
                if isequal(size(actual(k).Chunk.Samples),size(reference(k).Chunk.Samples))
                    difference=abs(double(actual(k).Chunk.Samples)-double(reference(k).Chunk.Samples));
                    fprintf('SHARED_TX_RADIATION_SAMPLE_MISMATCH interval=%d direction=%s output=%s max_abs=%.17g nonidentical=%d\n', ...
                        index,direction,string(actual(k).ID),max(difference,[],'all'),nnz(difference));
                else
                    fprintf('SHARED_TX_RADIATION_SHAPE_MISMATCH interval=%d direction=%s output=%s actual=%s reference=%s\n', ...
                        index,direction,string(actual(k).ID),mat2str(size(actual(k).Chunk.Samples)), ...
                        mat2str(size(reference(k).Chunk.Samples)));
                end
            end
            assert(actual(k).Chunk.StartSample==reference(k).Chunk.StartSample&& ...
                actual(k).Chunk.EndSample==reference(k).Chunk.EndSample&& ...
                isequaln(actual(k).Chunk.Samples,reference(k).Chunk.Samples), ...
                'Radiation recording changed actual RF/channel/noise output.');
        end
        for k=1:numel(execution.TX)
            measured=execution.TX(k).Replay;
            receipt=measured.ModeledRadiation;
            assert(receipt.OriginalRFIntervalVerified&&~receipt.ProductionOwnerIntegrationVerified&& ...
                ~receipt.HardwareConformanceVerified&&~receipt.AcceptedFeedPowerQualified);
            assert(isequaln(rmfield(measured,'ModeledRadiation'),plainExecution.TX(k).Replay));
        end
        binding=execution.Links.Replay.TXRadiationInstallation;
        assert(binding.Direction==string(direction)&& ...
            binding.StateKey==string(execution.Links.Replay.RuntimeChannelStateKey)&& ...
            binding.NativeGetter=="current_TransmitAntennaArray_no_second_swap");
        assert(isequaln(rmfield(execution.Links.Replay,'TXRadiationInstallation'),plainExecution.Links.Replay));
        assert(isequaln(execution.RX,plainExecution.RX)&&original.NextSampleIndex==stop);
        executions{index}=execution;
    end
    function path=retainOwners(label)
        % System-object state is serialized NOW. Retaining a mutable handle
        % in a cell until a later failure would lose the pre-call evidence.
        enabledStates=original.channelStates(); plainStates=plain.channelStates();
        snapshot=struct('Label',string(label),'RNG',rng, ...
            'EnabledNextSample',original.NextSampleIndex,'PlainNextSample',plain.NextSampleIndex, ...
            'EnabledChannelStates',{enabledStates},'PlainChannelStates',{plainStates});
        for j=1:numel(enabledStates)
            snapshot.EnabledChannelStates{j}.Obj=matlab.System.saveObject(enabledStates{j}.Obj);
        end
        for j=1:numel(plainStates)
            snapshot.PlainChannelStates{j}.Obj=matlab.System.saveObject(plainStates{j}.Obj);
        end
        path=fullfile(auditRoot,[label '_native_state.mat']);
        save(path,'snapshot','-v7.3');
    end
end

function n=tailSamples(cfg,channel,direction)
% The original outgoing RF delay/finite PA memory precedes the channel FIR.
% Consume it; never pad an RX observation or waive the owner's retarget guard.
resolved=sixgr.rf.applyRFImpairmentChain([],cfg,'SampleRateHz',channel.SampleRate_Hz, ...
    'Endpoint','tx','Direction',direction,'UseLegacyGlobalConfig',false,'ResolveOnly',true);
n=double(channel.ChannelPadSamples)+1;
if resolved.Config.TxTiming.Enabled, n=n+double(resolved.Config.TxTiming.TimingOffset_samples); end
if resolved.Config.TxPA.Enabled
    [profile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,direction);
    assert(canonical);
    if string(profile.Model)=="memory_polynomial", n=n+double(profile.MemoryDepth)-1; end
end
end

function policyChecks(declaration)
disabled=sixgr.rf.resolveModeledRadiationPolicy(struct('enabled',false));
assert(isequal(disabled,struct('Enabled',false)));
bad=declaration; bad.azimuth_count=1.5;
reject(@()sixgr.rf.resolveModeledRadiationPolicy(bad),'RF:ModeledRadiationPolicy');
bad=declaration; bad.ue_reference.rf_type='1-O';
reject(@()sixgr.rf.resolveModeledRadiationPolicy(bad),'RF:ModeledRadiationPolicy');
bad=declaration; bad.coordinate_frame=["installed_array_local_coordinates","global"];
reject(@()sixgr.rf.resolveModeledRadiationPolicy(bad),'RF:ModeledRadiationPolicy');
bad=rmfield(declaration,'ue_reference');
reject(@()sixgr.rf.resolveModeledRadiationPolicy(bad),'RF:ModeledRadiationPolicy');
end

function atomicChecks(e,executions)
ledger=sixgr.truth.RFEndpointExecutionLedger(e.SampleRateHz,e.OriginSample,e.ConfigurationEpoch,e.Inventory);
ledger.installRadiationLibrary(e.TXRadiationLibrary);
ledger.append(executions{1}); before=ledger.read();
for variant=1:6
    bad=executions{2};
    switch variant
        case 1, bad.TX(1).Replay.ModeledRadiation.ModelTRP_mW=42;
        case 2, bad.TX(1).Replay.ModeledRadiation.RFOutputWaveformSHA256=string(repmat('0',1,64));
        case 3, bad.TX(1).Replay.ModeledRadiation.PhysicalConfigurationEpoch=e.ConfigurationEpoch+1;
        case 4, bad.Links.Replay.TXRadiationInstallation.StateKey='different_native_link';
        case 5, bad.TX(1).Replay.ModeledRadiation.StartSample=bad.StartSample+1;
        case 6, bad.TX(1).Replay.ModeledRadiation.FieldSHA256=string(repmat('0',1,64));
    end
    reject(@()ledger.append(bad),'sixgr:truth:ModeledRadiationClosure');
    assert(isequaln(before,ledger.read()),'Rejected radiation must not partly commit RF/field evidence.');
end
bad=executions{2}; bad.Links.Replay=rmfield(bad.Links.Replay,'TXRadiationInstallation');
reject(@()ledger.append(bad),'sixgr:truth:ModeledRadiationMissing');
assert(isequaln(before,ledger.read()));
ledger.append(executions{2}); assert(ledger.NextSampleIndex==bad.EndSampleExclusive);
end

function publicationChecks(cfg,e)
folder=tempname; mkdir(folder); air=fullfile(folder,'air_interface'); mkdir(air);
cfg.meta.configHash=repmat('b',1,64);
cfg.run.executionID='declared_shared_radiation_component';
cfg.run.runTag='declared_shared_radiation_component';
cfg.run.scenarioID='declared_shared_radiation_component';
raw=struct('RFEndpointExecutionEvidence',e);
a=sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,raw);
assert(a.Available&&a.ModeledRadiationCSV~=""&&a.RadiationFieldMAT~="");
fieldHash=sixgr.util.sha256File(a.RadiationFieldMAT);
again=sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,raw);
assert(string(fieldHash)==string(sixgr.util.sha256File(again.RadiationFieldMAT)), ...
    'The immutable field archive must not be rewritten on report refresh.');
read=sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct());
assert(~read.PhysicalReplayExecuted&&read.Evidence.ModeledRadiationCompleteFromOrigin&& ...
    isequaln(a.Evidence.TXRadiationIntervals,read.Evidence.TXRadiationIntervals)&& ...
    isequaln(a.Evidence.TXRadiationLibrary,read.Evidence.TXRadiationLibrary)&& ...
    isequaln(a.Evidence.TXRadiationNativeBindings,read.Evidence.TXRadiationNativeBindings));
changed=read.Evidence.TXRadiationIntervals; changed.ModelTRP_mW(1)=42;
sixgr.util.csvWriteTable(a.ModeledRadiationCSV,changed,'PreserveSchema',true,'RoundTripNumericText',true);
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,struct()),'sixgr:truth:ModeledRadiationFileHash');
sixgr.truth.publishRFEndpointExecutionLedger(cfg,air,raw);
bad=e; bad.TXRadiationLibrary(1).Field.H(1)=bad.TXRadiationLibrary(1).Field.H(1)+1;
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air, ...
    struct('RFEndpointExecutionEvidence',bad)),'RF:TXRadiationArchive');
bad=e; bad.TXRadiationIntervals.AcceptedFeedPowerQualified(1)=true;
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air, ...
    struct('RFEndpointExecutionEvidence',bad)),'sixgr:truth:ModeledRadiationClosure');
bad=e; bad.TXRadiationIntervals(1,:)=[];
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,air, ...
    struct('RFEndpointExecutionEvidence',bad)),'sixgr:truth:ModeledRadiationClosure');
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingGuard','Expected %s.',id);
end
