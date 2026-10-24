function ok=testSharedTXLinearReferenceIntegration()
% Actual shared RF/CDL on declared IQ, not decoded PHY or power accuracy.
% Independent physical owners compare enabled/disabled recording exactly.
% Checkpoint replay is a component continuity test, not a resumed campaign.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
parent=fullfile(pwd,'logs','shared_tx_linear_reference_integration');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('SHARED_TX_LINEAR_REFERENCE_AUDIT %s\n',folder);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
originalDeclaration=source.Data; declaration=originalDeclaration;
% The existing native 64/4 RF/channel installation is retained. Unrelated
% field integration and spatial-covariance recording are explicitly off.
declaration.power_and_rf_frontend.modeled_radiated_power.enabled=false;
declaration.power_and_rf_frontend.tx_spatial_power_enabled=false;
declaration.power_and_rf_frontend.tx_linear_reference=struct('enabled',true, ...
    'model',"fixed_first_order_pa_identity_dac", ...
    'classification',"optional_research_experiment");
sixgr.lls6g.config.validateScenarioConfig(declaration,'Kind',source.Kind, ...
    'AllowPartial',false,'Context','declared shared TX linear-reference component');
component=sixgr.lls6g.config.ScenarioConfig(declaration, ...
    'SourceFiles',source.SourceFiles,'ConfigPath',source.ConfigPath, ...
    'ConfigHash',sixgr.lls6g.config.hashResolvedScenario(declaration),'Kind',source.Kind);
assert(isequaln(source.Data,originalDeclaration)&&component.ConfigHash~=source.ConfigHash);
cfg=sixgr.lls6g.buildInternalConfig(component,folder);
assert(~cfg.rf.modeledRadiatedPower.Enabled&&~cfg.rf.txSpatialPowerEnabled);
policy=struct('Enabled',true,'Model',"fixed_first_order_pa_identity_dac", ...
    'Classification',"optional_research_experiment",'RequirementClass',"IMPLEMENTATION_POLICY");
assert(isequaln(cfg.rf.txLinearReference,policy));
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder, ...
    sixgr.truth.resolveMultiUserSpec(cfg),struct(),0);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
window=sixgr.truth.resolveTRSObservationWindow(dl,1);
slot=window.AbsoluteSlotNumbers(1)+1;
window=sixgr.truth.resolveTRSObservationWindow(dl,slot);
assert(window.ObservationStarts&&sixgr.truth.isActiveTRSOccasion(dl,slot));
prepared=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',slot);
tx=prepared.Tx; tx.Waveform=prepared.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(prepared.ReceiverConfig,tx,prepared.TxInfo);
channel=truth.RuntimeChannelState;
assert(isa(channel.Obj,'nrCDLChannel')&&channel.NumTxAnt==64&&channel.NumRxAnt==4&& ...
    channel.CurrentSampleIndex==0&&channel.Meta.RuntimeTDDReciprocityExact);
fs=channel.SampleRate_Hz; epoch=cfg.rf.configurationEpoch;
disabledDL=dl; disabledUL=ul;
disabledDL.rf.txLinearReference.Enabled=false;
disabledUL.rf.txLinearReference.Enabled=false;
before=rng;
enabled=makeOwner(dl,ul,channel);
disabled=makeOwner(disabledDL,disabledUL,sixgr.channel.ChannelFactory.forkRuntimeChannelState(channel));
assert(isequal(before,rng),'Original-owner registration must not consume global RNG.');
initial=enabled.readRFExecutionLedger(); library=initial.TXLinearReferenceLibrary;
assert(numel(library)==2&&isempty(initial.TXLinearReferenceIntervals)&& ...
    ~initial.TXLinearReferenceCompleteFromOrigin);
assertLibrary(library);
enabled.validateTransmitterInstallation('gnb',dl,'DL',64);
enabled.validateTransmitterInstallation('ue',ul,'UL',4);
for field=["Enabled","Model","Classification","RequirementClass"]
    changed=dl;
    if field=="Enabled"
        changed.rf.txLinearReference.Enabled=false;
        expectedError='RF:TXLinearReferenceInstallationChanged';
    else
        changed.rf.txLinearReference.(field)="changed_declared_policy";
        expectedError='RF:TXLinearReferencePolicy';
    end
    reject(@()enabled.validateTransmitterInstallation('gnb',changed,'DL',64), ...
        expectedError);
end
assert(isequaln(initial,enabled.readRFExecutionLedger())&&enabled.NextSampleIndex==0&&~enabled.Faulted);
restored=struct(); executions=cell(7,1); serializedExtra=zeros(7,1);
runInterval(37,"DL",false,1);
runInterval(tailSamples(dl,channel,'DL'),"DL",true,2);
checkpoint=fullfile(folder,'original_owners_before_UL_checkpoint.mat');
save(checkpoint,'enabled','disabled','-v7.3');
checkpointSHA=string(sixgr.util.sha256File(checkpoint));
restored=load(checkpoint,'enabled','disabled');
assert(~isequal(restored.enabled,enabled)&&~isequal(restored.disabled,disabled), ...
    'A checkpoint must restore independent owner handles.');
assert(isequaln(restored.enabled.readRFExecutionLedger(),enabled.readRFExecutionLedger())&& ...
    isequaln(restored.disabled.readRFExecutionLedger(),disabled.readRFExecutionLedger()));
retarget("UL");
runInterval(41,"UL",false,3);
runInterval(tailSamples(ul,channel,'UL'),"UL",true,4);
retarget("DL");
runInterval(23,"DL",false,5);
% Longer interval detects accidentally retained PN/CFO arrays. It is still
% a small declared component, not a full slot or scenario execution.
runInterval(1025,"DL",false,6);
assert(serializedExtra(6)-serializedExtra(5)<128*1024, ...
    'test:TXLinearReferenceRetainedOperator', ...
    'Owner growth must be compact interval receipts, not sample-sized operators.');
runInterval(19,"DL",false,7);
assert(isequal(before,rng)&&string(sixgr.util.sha256File(checkpoint))==checkpointSHA, ...
    'Checkpoint/readback/reference recording changed original bytes or global RNG.');
e=enabled.readRFExecutionLedger(); plain=disabled.readRFExecutionLedger();
assert(e.CompleteFromOrigin&&e.TXLinearReferenceCompleteFromOrigin&& ...
    height(e.TXLinearReferenceIntervals)==14&&isequaln(library,e.TXLinearReferenceLibrary));
assert(isempty(plain.TXLinearReferenceLibrary)&&isempty(plain.TXLinearReferenceIntervals)&& ...
    ~plain.TXLinearReferenceCompleteFromOrigin);
for field=["Intervals","ChainPowerIntervals","TXSpatialPowerIntervals"]
    assert(isequaln(e.(field),plain.(field)), ...
        'Existing actual RF tables must remain identical when model recording is enabled.');
end
assert(isequaln(e,restored.enabled.readRFExecutionLedger())&& ...
    isequaln(plain,restored.disabled.readRFExecutionLedger()));
noSampleOperators(e); noSampleOperators(plain);
scope=struct('ActualSharedRFAndNativeChannel',true,'DeclaredIQInput',true, ...
    'NativeRetargetCount',2,'OriginalOwnerIntervalCount',7,'OriginalTXReceiptCount',14, ...
    'CheckpointContinuationCompared',true,'DecodedPHY',false, ...
    'ReceivedCSIPowerAccuracyQualified',false,'NonlinearPortAttributionQualified',false, ...
    'StandardizedPowerAccuracyQualified',false,'HardwareQualified',false);
save(fullfile(folder,'shared_tx_linear_reference_original_audit.mat'), ...
    'e','plain','executions','scope','serializedExtra','checkpointSHA','component','-v7.3');
fprintf(['SHARED_TX_LINEAR_REFERENCE_INTEGRATION_PASS actual_RF_channel_intervals=7 ' ...
    'TX_receipts=14 native_retargets=2 exact_samples=1 checkpoint_continuation=1 ' ...
    'decoded_PHY=0 received_power_accuracy=0 hardware=0\n']);
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
    function retarget(direction)
        if direction=="UL", txID='ue'; rxID='gnb_rx'; active=ul; quiet=disabledUL;
        else, txID='gnb'; rxID='ue_rx'; active=dl; quiet=disabledDL; end
        owners={enabled,disabled,restored.enabled,restored.disabled};
        configurations={active,quiet,active,quiet};
        for k=1:numel(owners)
            owner=owners{k}; prior=owner.NextSampleIndex; selected=configurations{k};
            owner.retargetTDDLink('serving',txID,rxID,selected);
            assert(owner.NextSampleIndex==prior);
        end
        assertChannelClocks(enabled,disabled);
        assertChannelClocks(enabled,restored.enabled);
    end
    function runInterval(n,direction,idle,index)
        first=enabled.NextSampleIndex; stop=first+n;
        assert(disabled.NextSampleIndex==first);
        x=complex(zeros(n,64)); u=complex(zeros(n,4));
        if ~idle
            if direction=="DL", x=reshape(.01*exp(1i*(1:n*64)/19),n,64);
            else, u=reshape(.01*exp(1i*(1:n*4)/23),n,4); end
        end
        inputs(1)=struct('ID',"gnb",'Chunk',sixgr.phy.waveform.WaveformChunk(x,first));
        inputs(2)=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk(u,first));
        stateBefore=channelSnapshots(enabled,disabled); rngBefore=rng;
        save(fullfile(folder,sprintf('interval_%02d_original_before.mat',index)), ...
            'inputs','first','stop','stateBefore','rngBefore','-v7.3');
        [actual,execution]=enabled.process(inputs,first,stop,[]);
        [reference,plainExecution]=disabled.process(inputs,first,stop,[]);
        checkpointActual=[]; checkpointReference=[]; checkpointExecution=[]; checkpointPlainExecution=[];
        if ~isempty(fieldnames(restored))
            [checkpointActual,checkpointExecution]=restored.enabled.process(inputs,first,stop,[]);
            [checkpointReference,checkpointPlainExecution]=restored.disabled.process(inputs,first,stop,[]);
        end
        interval=struct('Index',index,'Direction',direction,'Idle',idle,'Inputs',inputs, ...
            'Actual',actual,'Reference',reference,'Execution',execution,'PlainExecution',plainExecution, ...
            'CheckpointActual',checkpointActual,'CheckpointReference',checkpointReference, ...
            'CheckpointExecution',checkpointExecution,'CheckpointPlainExecution',checkpointPlainExecution, ...
            'OriginalNativeStatesBefore',stateBefore,'RNGBefore',rngBefore,'RNGAfter',rng);
        save(fullfile(folder,sprintf('interval_%02d_original_operands.mat',index)),'interval','-v7.3');
        assertOutputs(actual,reference,index);
        assert(isequaln(execution.TX,plainExecution.TX)&&isequaln(execution.RX,plainExecution.RX)&& ...
            isequaln(execution.Links,plainExecution.Links));
        assert(isempty(plainExecution.TXLinearReferences));
        assertReferences(execution,inputs,actual,library);
        if ~isempty(fieldnames(restored))
            assertOutputs(actual,checkpointActual,index);
            assertOutputs(reference,checkpointReference,index);
            assert(isequaln(execution,checkpointExecution)&&isequaln(plainExecution,checkpointPlainExecution), ...
                'Checkpoint restoration changed original execution or model evidence.');
            assertChannelClocks(enabled,restored.enabled);
        end
        assert(isequal(rngBefore,rng)&&enabled.NextSampleIndex==stop&&disabled.NextSampleIndex==stop);
        assertChannelClocks(enabled,disabled);
        current=enabled.readRFExecutionLedger(); other=disabled.readRFExecutionLedger();
        assert(height(current.TXLinearReferenceIntervals)==2*index&&current.TXLinearReferenceCompleteFromOrigin);
        assert(isequaln(library,current.TXLinearReferenceLibrary)&&isempty(other.TXLinearReferenceIntervals));
        noSampleOperators(current);
        serializedExtra(index)=numel(getByteStreamFromArray(enabled))-numel(getByteStreamFromArray(disabled));
        executions{index}=execution;
        fprintf('SHARED_TX_LINEAR_REFERENCE_INTERVAL %d %s samples=%d original_TX_receipts=%d exact=1\n', ...
            index,direction,n,numel(execution.TXLinearReferences));
    end
    function assertLibrary(items)
        for k=1:numel(items)
            c=items(k);
            assert(string(c.ContractVersion)=="sixgr.rf.installed_TX_linear_reference/v1"&& ...
                any(string(c.EndpointID)==["gnb","ue"])&&c.ConfigurationEpoch==epoch&& ...
                c.SampleRateHz==fs&&c.OriginSample==0&&isequaln(c.Policy,policy));
            if string(c.EndpointID)=="gnb", n=64; d="DL"; conf=dl;
            else, n=4; d="UL"; conf=ul; end
            pctx=sixgr.rf.PowerContext(conf,d);
            assert(c.NumAntennas==n&&string(c.Direction)==d&& ...
                string(c.WaveformAmplitudeUnit)==string(pctx.WaveformAmplitudeUnit));
            assertHash(c.RegistrationSHA256); assertHash(c.RFChainSHA256);
        end
        assert(numel(unique(string({items.EndpointID})))==2);
    end
end

function assertReferences(execution,inputs,outputs,library)
records=execution.TXLinearReferences;
assert(numel(records)==numel(execution.TX)&&numel(unique(string({records.ID})))==numel(records));
for entry=records
    id=string(entry.ID); r=entry.Receipt; a=r.Adapter;
    src=inputs(string({inputs.ID})==id).Chunk;
    dst=outputs(string({outputs.ID})==id+":tx").Chunk;
    rf=execution.TX(string({execution.TX.ID})==id).Replay;
    c=library(string({library.EndpointID})==id);
    assert(isscalar(c)&&string(r.ContractVersion)=="sixgr.rf.original_owner_TX_linear_reference/v1"&& ...
        string(r.Source)=="original_registered_TX_RF_owner_fixed_linear_diagnostic_model"&& ...
        string(r.RegistrationSHA256)==string(c.RegistrationSHA256)&& ...
        string(r.OriginalInputChunkSHA256)==src.SHA256&&string(r.OriginalOutputChunkSHA256)==dst.SHA256&& ...
        r.OriginalOwnerBindingVerified&&~r.ReceiverEstimatorInput&& ...
        r.AdditionalRFExecutions==0&&r.AdditionalChannelExecutions==0);
    assert(string(a.Role)=="aggregate"&&string(a.EndpointID)==id&& ...
        string(a.Direction)==string(c.Direction)&&a.ConfigurationEpoch==execution.ConfigurationEpoch&& ...
        a.SampleRateHz==execution.SampleRateHz&&a.NumAntennas==c.NumAntennas&& ...
        a.StartSample==execution.StartSample&&a.EndSampleExclusive==execution.EndSampleExclusive&& ...
        a.OriginSample==c.OriginSample&&a.ModelHistoryStartSample==c.OriginSample&& ...
        string(a.InstallationSHA256)==string(c.RegistrationSHA256)&& ...
        string(a.WaveformAmplitudeUnit)==string(c.WaveformAmplitudeUnit)&& ...
        string(a.OriginalRFInputSHA256)==string(rf.RFInputWaveformSHA256)&& ...
        string(a.OriginalRFOutputSHA256)==string(rf.RFOutputWaveformSHA256)&& ...
        string(a.ModelInputSHA256)==sixgr.phy.waveform.WaveformHash.runtimeArray(src.Samples));
    assert(a.ResidualAvailable&&~a.OriginalOwnerVerified&&~a.SharedRuntimeIntegrationQualified&& ...
        ~a.ActualNonlinearPortAttribution&&~a.StandardizedPowerAccuracyQualified&&~a.HardwareQualified&& ...
        ~a.ReceiverEstimatorInput&&a.AdditionalRFExecutions==0&&a.AdditionalChannelExecutions==0);
    actualEnergy=sum(abs(double(dst.Samples(:))).^2);
    closure=a.ReferenceEnergy+a.ResidualEnergy+a.ReferenceResidualCrossEnergy;
    % Double-precision reductions have a length-dependent forward error.
    % A fixed 256-ulp bound failed on 65,600 unchanged complex samples.
    % Bound the norm squares, residual subtraction and signed dot product
    % conservatively; include the absolute dot-product bound, not just its
    % potentially cancelled signed value. This does not alter samples,
    % exported energies, exact hash/energy checks or the relative-error gate.
    n=numel(dst.Samples); u=eps('double')/2; operations=8*n+16;
    assert(operations*u<1);
    gamma=operations*u/(1-operations*u);
    energyScale=actualEnergy+a.ReferenceEnergy+a.ResidualEnergy+ ...
        2*sqrt(a.ReferenceEnergy)*sqrt(a.ResidualEnergy);
    closureBound=gamma*energyScale;
    assert(a.ActualAggregateOutputEnergy==actualEnergy&& ...
        abs(actualEnergy-closure)<=closureBound&&a.PowerClosureRelativeError<1e-12);
    for field=["ReferenceOutputSHA256","StaticOperatorSHA256","IntervalOperatorSHA256", ...
            "ModelPAStateSHA256","ModelDelayStateSHA256","ResidualSHA256"]
        assertHash(a.(field));
    end
    noSampleOperators(r);
end
end

function assertOutputs(actual,expected,index)
assert(isequal(string({actual.ID}),string({expected.ID})));
for k=1:numel(actual)
    a=actual(k).Chunk; b=expected(k).Chunk;
    if ~isequaln(a.Samples,b.Samples)
        fprintf('SHARED_TX_LINEAR_REFERENCE_MISMATCH interval=%d output=%s\n',index,string(actual(k).ID));
    end
    assert(a.StartSample==b.StartSample&&a.EndSample==b.EndSample&&a.SHA256==b.SHA256&& ...
        isequaln(a.Samples,b.Samples),'test:SharedTXLinearReferenceSamples', ...
        'Reference recording/restoration changed original physical samples.');
end
end

function snapshots=channelSnapshots(a,b)
snapshots=struct('Enabled',{a.channelStates()},'Disabled',{b.channelStates()});
for name=["Enabled","Disabled"]
    for k=1:numel(snapshots.(name))
        snapshots.(name){k}.Obj=matlab.System.saveObject(snapshots.(name){k}.Obj);
    end
end
end

function assertChannelClocks(a,b)
x=a.channelStates(); y=b.channelStates(); assert(numel(x)==numel(y));
for k=1:numel(x)
    for field=["StateKey","Direction","CurrentSampleIndex","TotalAppliedSamples", ...
            "TotalIdleAdvancedSamples","WarmupSamples","ResetCount","NumTxAnt","NumRxAnt"]
        assert(isequaln(x{k}.(field),y{k}.(field)),'Original native channel clock/layout changed.');
    end
    assert(isequal(x{k}.Obj.TransmitAndReceiveSwapped,y{k}.Obj.TransmitAndReceiveSwapped));
end
end

function n=tailSamples(cfg,channel,direction)
resolved=sixgr.rf.applyRFImpairmentChain([],cfg,'SampleRateHz',channel.SampleRate_Hz, ...
    'Endpoint','tx','Direction',direction,'UseLegacyGlobalConfig',false,'ResolveOnly',true);
n=double(channel.ChannelPadSamples)+1;
if resolved.Config.TxTiming.Enabled, n=n+double(resolved.Config.TxTiming.TimingOffset_samples); end
if resolved.Config.TxPA.Enabled
    [profile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,direction); assert(canonical);
    if string(profile.Model)=="memory_polynomial", n=n+double(profile.MemoryDepth)-1; end
end
end

function noSampleOperators(value)
if istable(value), value=table2struct(value); end
if isstruct(value)
    for k=1:numel(value)
        for name=string(fieldnames(value(k))).'
            assert(~any(name==["Phase_rad","Multiplier","Stages","OriginalTXOperatorCapture", ...
                "Waveform","Samples","ReferenceSamples","ResidualSamples"]), ...
                'test:SharedTXLinearReferenceCompact','Sample-sized operators must stay outside compact evidence.');
            noSampleOperators(value(k).(name));
        end
    end
elseif iscell(value)
    for k=1:numel(value), noSampleOperators(value{k}); end
end
end

function assertHash(value)
assert(isscalar(string(value))&&~isempty(regexp(char(string(value)),'^[0-9a-f]{64}$','once')));
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'test:SharedTXLinearReferenceWrongError', ...
        'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:SharedTXLinearReferenceMissingError','Expected %s.',id);
end
