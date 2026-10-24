function ok=testAppliedChannelReferenceStream()
% Actual native ChannelFactory/dependency/reference component, not a shared
% owner, CSI port attribution, receiver oracle, or power-accuracy claim.
% Endpoint wrapper and component decomposition below are declared fixtures.
% Normalization-off TDD exercises real reciprocal retargets. Normalization-on
% is rejected for TDD, then exercised only on fresh fixed-direction FDD.
% Late births reuse these ORIGINAL executed intervals. Their registration
% and input decomposition are declared component fixtures, not queue/RF-owner
% evidence; zero component history is never copied from aggregate history.
setup6GRSimToolkit('Verbose',false);
parent=fullfile(pwd,'logs','applied_channel_reference_stream');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('APPLIED_CHANNEL_REFERENCE_AUDIT %s\n',folder);
originalRNG=rng; results={}; failures={};
for normalizeOutputs=[false true]
    for initialDirection=["DL","UL"]
        duplex="TDD_reciprocal";
        if normalizeOutputs, duplex="FDD_fixed_direction"; end
        name=initialDirection+"_"+duplex+"_normalize_outputs_"+string(normalizeOutputs);
        try
            results{end+1}=nativeCase(name,normalizeOutputs,initialDirection,folder); %#ok<AGROW>
        catch cause
            failures{end+1}=struct('Name',name,'Identifier',string(cause.identifier), ...
                'Report',string(getReport(cause,'extended','hyperlinks','off'))); %#ok<AGROW>
            fprintf('APPLIED_CHANNEL_REFERENCE_CASE_FAIL %s %s\n',name,cause.identifier);
        end
    end
end
finalRNG=rng;
save(fullfile(folder,'summary.mat'),'results','failures','originalRNG','finalRNG','-v7.3');
assert(isequal(originalRNG,finalRNG),'test:AppliedReferenceRNG','Global RNG changed.');
assert(isempty(failures),'test:AppliedReferenceFailed', ...
    '%d native component case(s) failed; originals retained at %s.',numel(failures),folder);
fprintf(['PASS testAppliedChannelReferenceStream: two reciprocal TDD cases, ' ...
    'two fixed-direction FDD cases, two exact TDD normalization rejections, ' ...
    'late-component birth/tail/native-clock guards; shared integration=0.\n']);
ok=true;
end

function result=nativeCase(name,normalizeOutputs,initialDirection,folder)
cfg=sixgr.config.defaultConfig(); fs=7.68e6; seed=65537; epoch=9;
cfg.run.seed=seed; cfg.channel.seed=seed;
cfg.channel.model='CDL-C'; cfg.channel.cdlProfile='CDL-C'; cfg.channel.delayProfile='CDL-C';
cfg.channel.fading.model='CDL'; cfg.channel.fading.profile='CDL-C';
cfg.channel.awgnOnly=false; cfg.channel.delaySpread_s=100e-9; cfg.channel.doppler_Hz=37;
cfg.channel.channelFiltering=true; cfg.channel.perSampleFadingEnabled=true;
cfg.channel.normalizePathGains=~normalizeOutputs;
cfg.channel.normalizeChannelOutputs=normalizeOutputs;
cfg.phy.fc_Hz=2.35e9; cfg.phy.duplex.mode='TDD';
cfg.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
cfg.channel.pathlossEnabled=true; cfg.channel.pathloss_dB=7;
cfg.lls6g.userContext.RuntimeCurrentDirection=char(initialDirection);
cfg.integration.run_mode='CONNECTED_NETWORK';
cfg.integration.configured_snr_is_link_authority=false;
nt=4; nr=2; if initialDirection=="UL", nt=2; nr=4; end
txInfo=struct('OFDM',struct('SampleRate',fs));
caseFolder=fullfile(folder,char(name)); mkdir(caseFolder);
normalizationRejection=struct([]);
if normalizeOutputs
    % This is a separate expected-negative. Do not bypass the production
    % reciprocal amplitude guard or count its rejection as waveform proof.
    assert(sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD");
    forbidden=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,initialDirection, ...
        'LinkKey',"declared_forbidden_normalized_TDD",'Seed',seed,'AbsoluteSampleIndex',73);
    beforeRejectionRNG=rng; expected="ChannelFactory:DynamicTDDOutputNormalizationForbidden";
    try
        sixgr.channel.ChannelFactory.materializeRuntimeChannelState(forbidden,cfg, ...
            complex(zeros(37,nt)),txInfo,'NumTxAnt',nt,'NumRxAnt',nr);
    catch cause
        assert(string(cause.identifier)==expected,'test:AppliedReferenceWrongTDDRejection', ...
            'Expected %s; got %s: %s',expected,cause.identifier,cause.message);
        normalizationRejection=struct('Direction',initialDirection,'Duplex',"TDD", ...
            'ObservedIdentifier',string(cause.identifier),'Message',string(cause.message), ...
            'Expectation',"normalization_on_reciprocal_TDD_forbidden", ...
            'SuccessfulWaveformExecution',false);
    end
    assert(~isempty(normalizationRejection),'test:AppliedReferenceMissingTDDRejection', ...
        'Expected the unchanged production TDD normalization guard.');
    assert(isequal(rng,beforeRejectionRNG),'test:AppliedReferenceRejectionRNG');
    save(fullfile(caseFolder,'tdd_normalization_rejection.mat'), ...
        'normalizationRejection','cfg','-v7.3');
    % A new FDD installation is independent of the rejected TDD attempt.
    % The common fresh-materialization producer supplies the initialization
    % receipt; no receipt, filter authority, or history is manufactured here.
    cfg.phy.duplex.mode='FDD';
end
duplex=sixgr.phy.frame.resolveDuplexMode(cfg);
assert((normalizeOutputs&&duplex=="FDD")||(~normalizeOutputs&&duplex=="TDD"));
native=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,initialDirection, ...
    'LinkKey',"declared_applied_reference_component",'Seed',seed,'AbsoluteSampleIndex',73);
native=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(native,cfg, ...
    complex(zeros(37,nt)),txInfo,'NumTxAnt',nt,'NumRxAnt',nr);
dependency=sixgr.channel.ChannelSignalDependency.install(native,epoch);
assert(dependency.Available&&native.CurrentSampleIndex==73&&native.TotalAppliedSamples==0);
nativeInitialization=native.Meta.NativeReciprocalFilterInitialization;
assert(nativeInitialization.Applied && ...
    string(nativeInitialization.Status)=="fresh_public_both_direction_setup_then_reset" && ...
    native.Obj.NormalizeChannelOutputs==normalizeOutputs && ...
    native.Obj.NormalizePathGains==~normalizeOutputs && ...
    dependency.NativeInitializationSHA256==string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(nativeInitialization),'UTF-8')))));
save(fullfile(caseFolder,'original_installation.mat'), ...
    'cfg','dependency','nativeInitialization','duplex','-v7.3');
binding=makeBinding(initialDirection,epoch);
stream=sixgr.channel.AppliedChannelReferenceStream(binding,dependency);
componentA=stream; componentB=stream;
% A distinct original native state demonstrates observation does not change
% the executed waveform. Capture/no-capture keep the canonical partition.
unobserved=sixgr.channel.ChannelFactory.forkRuntimeChannelState(native);
records={}; guard=max(native.ChannelPadSamples+1,dependency.MemorySamples+1);
execute('head',signal(37,nt,1));
execute('continuation',signal(41,nt,2));
execute('outgoing_zero_tail',complex(zeros(guard,nt)));
if duplex=="TDD"
    opposite="UL"; if initialDirection=="UL", opposite="DL"; end
    retarget(opposite,nr,nt,guard);
    execute('reverse_head',signal(23,nr,3));
    execute('reverse_continuation',signal(19,nr,4));
    execute('reverse_zero_tail',complex(zeros(guard,nr)));
    retarget(initialDirection,nt,nr,guard);
    execute('returned_head',signal(17,nt,5));
end
% All negatives are value copies of the first ORIGINAL execution. No native
% call, reset, receiver operation or invented gain tensor is used here.
negativeCount=negatives(records{1});
lateBirth=lateBirthCases(records,caseFolder);
result=struct('Name',name,'Duplex',duplex, ...
    'ReciprocalRetargetExercised',duplex=="TDD", ...
    'ExpectedTDDNormalizationRejection',normalizationRejection, ...
    'OriginalNativeInitialization',nativeInitialization,'OriginalNormalizationFlags', ...
    [~normalizeOutputs normalizeOutputs],'Intervals',{records},'NegativeCount',negativeCount, ...
    'LateComponentBirth',lateBirth, ...
    'FinalPhysicalSample',native.CurrentSampleIndex,'SharedRuntimeIntegrationQualified',false, ...
    'PortAttributionQualified',false,'ReceiverExecuted',false);
save(fullfile(caseFolder,'result.mat'),'result','-v7.3');
fprintf('APPLIED_CHANNEL_REFERENCE_CASE_PASS %s intervals=%d negatives=%d\n', ...
    name,numel(records),negativeCount);

    function execute(phase,x)
        before=native; oldStream=stream; oldA=componentA; oldB=componentB;
        originalBeforeSnapshot=sixgr.channel.ChannelSignalDependency.beforeRetarget(native);
        input=sixgr.phy.waveform.WaveformChunk(x,before.CurrentSampleIndex);
        [actual,replay,native,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
            native,x,'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
            'OutputSampleAlignment','continuous_raw_samples');
        replay.ChannelSignalDependency=sixgr.channel.ChannelSignalDependency.bind( ...
            dependency,before,native,replay,before.CurrentSampleIndex,native.CurrentSampleIndex);
        [untouched,~,unobserved]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
            unobserved,x,'CaptureChannelReference',false,'InputSampleDomain','materialized_channel_ports', ...
            'OutputSampleAlignment','continuous_raw_samples');
        assert(isequal(actual,untouched)&&native.CurrentSampleIndex==unobserved.CurrentSampleIndex && ...
            native.TotalObjectInputSamples==unobserved.TotalObjectInputSamples, ...
            'test:AppliedReferenceObservationMutation','Reference capture changed original native samples/state.');
        [desired,loss]=sixgr.link.applyWaveformImpairments(actual,cfg,fs,'ApplyRFChain',false);
        assert(loss.AppliedLargeScaleAmplitudeGain~=1, ...
            'test:AppliedReferenceLossFixture','This test must exercise a nonunit ORIGINAL loss.');
        link=struct('ID',binding.LinkID,'TX',binding.TX,'RX',binding.RX, ...
            'Replay',replay,'LossReplay',loss);
        % Save original inputs and operator before the adapter or assertions.
        original=struct('Input',input,'Reference',reference,'LinkExecution',link, ...
            'ActualNative',actual,'ActualDesired',desired,'StreamBefore',oldStream, ...
            'OriginalBeforeSnapshot',originalBeforeSnapshot, ...
            'DeclaredBinding',binding,'EndpointWrapperScope',"declared_native_component_not_shared_owner");
        save(fullfile(caseFolder,[phase '_original.mat']),'original','-v7.3');
        beforeRNG=rng; nativeInfo=info(native.Obj);
        [stream,predicted,predictedDesired,receipt]=stream.advance(x,input,reference,link);
        % Two declared linear input components share the same original
        % operator and aggregate identity, with independent FIR state.
        xa=x; xa(:,2:2:end)=0; xb=x-xa;
        [componentA,ya,da,ra]=componentA.advance(xa,input,reference,link);
        [componentB,yb,db,rb]=componentB.advance(xb,input,reference,link);
        assert(isequal(rng,beforeRNG)&&isequaln(info(native.Obj),nativeInfo) && ...
            oldStream.NextSampleIndex==before.CurrentSampleIndex && ...
            oldA.NextSampleIndex==oldStream.NextSampleIndex&&oldB.NextSampleIndex==oldStream.NextSampleIndex, ...
            'test:AppliedReferenceNotValueState');
        nativeError=relative(predicted,actual); desiredError=relative(predictedDesired,desired);
        sumError=relative(ya+yb,predicted);
        assert(nativeError<1e-11&&desiredError<1e-11&&sumError<1e-12 && ...
            relative(da+db,predictedDesired)<1e-12, ...
            'test:AppliedReferenceArithmetic','Full sample-domain/native equality failed.');
        assert(isequal(predictedDesired,predicted.*loss.AppliedLargeScaleAmplitudeGain) && ...
            receipt.LossApplicationCount==1&&~receipt.AdditionalNormalizationApplied && ...
            receipt.ReferenceNormalizeChannelOutputs==normalizeOutputs && ...
            receipt.ReferenceNormalizePathGains==~normalizeOutputs && ~receipt.NormalizationFlagsVerified && ...
            receipt.OriginalAggregateInputSHA256==string(reference.InputWaveformSHA256) && ...
            receipt.ComponentInputSHA256==receipt.OriginalAggregateInputSHA256 && ...
            ra.OriginalAggregateInputSHA256==rb.OriginalAggregateInputSHA256 && ...
            ~receipt.SharedRuntimeIntegrationQualified&&~receipt.PortAttributionQualified && ...
            ~receipt.StandardizedPowerAccuracyQualified&&receipt.AdditionalChannelExecutions==0);
        if any(x~=0,'all')
            assert(ra.ComponentInputSHA256~=ra.OriginalAggregateInputSHA256 && ...
                rb.ComponentInputSHA256~=rb.OriginalAggregateInputSHA256);
        end
        % Cross terms are needed for coherent declared components; do not
        % equate sum of separate component powers with total power.
        totalEnergy=sum(abs(predicted(:)).^2);
        closedEnergy=sum(abs(ya(:)).^2)+sum(abs(yb(:)).^2)+2*real(sum(ya(:).*conj(yb(:))));
        assert(abs(totalEnergy-closedEnergy)<1e-12*max(realmin,totalEnergy));
        record=original; record.Receipt=receipt; record.NativeError=nativeError;
        record.DesiredError=desiredError; record.ComponentSumError=sumError;
        record.PredictedNative=predicted; record.PredictedDesired=predictedDesired;
        records{end+1}=record;
        save(fullfile(caseFolder,[phase '_comparison.mat']),'record','-v7.3');
    end

    function retarget(direction,nextTx,nextRx,consumedTail)
        originalBefore=sixgr.channel.ChannelSignalDependency.beforeRetarget(native);
        native.Direction=char(direction);
        native=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(native,cfg, ...
            complex(zeros(1,nextTx)),txInfo,'NumTxAnt',nextTx,'NumRxAnt',nextRx);
        unobserved.Direction=char(direction);
        unobserved=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(unobserved,cfg, ...
            complex(zeros(1,nextTx)),txInfo,'NumTxAnt',nextTx,'NumRxAnt',nextRx);
        dependency=sixgr.channel.ChannelSignalDependency.afterRetarget( ...
            originalBefore,native,epoch,consumedTail);
        nextBinding=makeBinding(direction,epoch);
        bad=dependency; bad.InitializationReceipt.After.NativeSwapped=originalBefore.NativeSwapped;
        reject(@()stream.retarget(nextBinding,bad),'History');
        bad=dependency; bad.InitializationReceipt.ElapsedIdleTimeUsedAsReset=true;
        reject(@()stream.retarget(nextBinding,bad),'History');
        bad=dependency; bad.InputHistoryStartSample=bad.InputHistoryStartSample+1;
        reject(@()stream.retarget(nextBinding,bad),'History');
        reject(@()sixgr.channel.AppliedChannelReferenceStream(nextBinding,dependency),'History');
        stream=stream.retarget(nextBinding,dependency);
        componentA=componentA.retarget(nextBinding,dependency);
        componentB=componentB.retarget(nextBinding,dependency);
        binding=nextBinding; cfg.lls6g.userContext.RuntimeCurrentDirection=char(direction);
        assert(stream.NextSampleIndex==native.CurrentSampleIndex&&native.ResetCount==originalBefore.ResetCount);
    end
end

function result=lateBirthCases(records,folder)
% No native channel call below. Propagate a declared component using the same
% retained operators both from the original zero origin and from its birth.
% The latter must not inherit the already-nonzero aggregate FIR state.
pairs=[1 2 3];
if numel(records)==7, pairs=[pairs; 4 5 6]; end
checks=cell(size(pairs,1),1); negativeCount=0;
beforeRNG=rng;
for k=1:size(pairs,1)
    head=records{pairs(k,1)}; current=records{pairs(k,2)}; tail=records{pairs(k,3)};
    baseline=head.StreamBefore;
    [baseline,zeroNative,zeroDesired]=baseline.advance( ...
        complex(zeros(size(head.Input.Samples))),head.Input,head.Reference,head.LinkExecution);
    assert(~any(zeroNative~=0,'all')&&~any(zeroDesired~=0,'all'));
    assert(any(head.Input.Samples~=0,'all') && ...
        current.OriginalBeforeSnapshot.TotalAppliedSamples> ...
        head.OriginalBeforeSnapshot.TotalAppliedSamples, ...
        'test:AppliedReferenceLateBirthFixture','Require real preceding nonzero aggregate execution.');
    birth=declaredBirth(current,k);
    d=current.StreamBefore.Dependency; originalD=d;
    originalSnapshot=current.OriginalBeforeSnapshot;
    late=sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth( ...
        current.DeclaredBinding,d,originalSnapshot,birth);
    assert(isequaln(late.Dependency,originalD)&&isequaln(late.OriginalBirthSnapshot,originalSnapshot) && ...
        late.NextSampleIndex==current.Input.StartSample && ...
        late.ModelHistoryStartSample==birth.ModelHistoryStartSample && ...
        late.ObjectTimeOffsetSamples==current.StreamBefore.ObjectTimeOffsetSamples && ...
        late.Dependency.InputHistoryStartSample<late.ModelHistoryStartSample, ...
        'test:AppliedReferenceLateBirthOrigin','Birth rewrote original native history or offset.');
    input=.3*current.Input.Samples;
    coordinates=current.Input.StartSample+(0:size(input,1)-1).';
    input(coordinates<birth.ComponentSupportStartSample,:)=0;
    assert(any(input(coordinates>=birth.ComponentSupportEndSampleExclusive,:)~=0,'all'), ...
        'test:AppliedReferenceLateBirthFixture','Declare a post-source-support channel-input tail.');
    % The source end is metadata, not a post-TX-RF support bound. This fixture
    % declares that upstream tail; it does not claim an RF producer ran here.
    saved=struct('Birth',birth,'OriginalSnapshot',originalSnapshot, ...
        'OriginalDependency',originalD,'ComponentInput',input, ...
        'SourceScope',"declared_component_input_using_original_executed_channel_operator");
    save(fullfile(folder,sprintf('late_birth_%d_original.mat',k)),'saved','-v7.3');
    [baseline,y0,z0]=baseline.advance(input,current.Input,current.Reference,current.LinkExecution);
    oldLate=late;
    [late,y,z,receipt]=late.advance(input,current.Input,current.Reference,current.LinkExecution);
    assert(isequal(y,y0)&&isequal(z,z0) && ...
        receipt.ObjectTimeOffsetSamples==current.Reference.ObjectTimeOffsetSamples && ...
        receipt.InputHistoryStartSample==originalD.InputHistoryStartSample && ...
        isequaln(receipt.ComponentBirth,birth)&&isequaln(receipt.OriginalBirthSnapshot,originalSnapshot) && ...
        ~receipt.OriginalOwnerVerified&&~receipt.SourceSupportEndAppliedAsTrim && ...
        ~receipt.SharedRuntimeIntegrationQualified&&~receipt.PortAttributionQualified && ...
        receipt.AdditionalChannelExecutions==0, ...
        'test:AppliedReferenceLateBirthArithmetic','Late birth differs from zero-from-origin component propagation.');
    % An aggregate-history copy must be numerically distinguishable from the
    % zero-prehistory component, not merely assigned a different label.
    [~,wrongHistory]=current.StreamBefore.advance(input,current.Input,current.Reference,current.LinkExecution);
    assert(norm(wrongHistory-y,'fro')>0,'test:AppliedReferenceLateBirthFixture', ...
        'The original aggregate history must be observably nonzero.');
    zerosAfter=complex(zeros(size(tail.Input.Samples)));
    [baseline,tail0,desiredTail0]=baseline.advance(zerosAfter,tail.Input,tail.Reference,tail.LinkExecution);
    [late,tailY,desiredTail,tailReceipt]=late.advance(zerosAfter,tail.Input,tail.Reference,tail.LinkExecution);
    assert(isequal(tailY,tail0)&&isequal(desiredTail,desiredTail0)&&any(tailY~=0,'all') && ...
        tailReceipt.StartSample>=birth.ComponentSupportEndSampleExclusive && ...
        baseline.NextSampleIndex==late.NextSampleIndex, ...
        'test:AppliedReferenceLateBirthTail','Channel FIR tail was lost at source support end.');
    negativeCount=negativeCount+lateBirthNegatives(current,oldLate,birth,input);
    if numel(records)>pairs(k,3)
        nextDirection=records{pairs(k,3)+1};
        reject(@()late.retarget(nextDirection.DeclaredBinding,nextDirection.StreamBefore.Dependency),'History');
        negativeCount=negativeCount+1;
    end
    checks{k}=struct('Birth',birth,'Receipt',receipt,'TailReceipt',tailReceipt, ...
        'OutputMatchesZeroFromOrigin',isequal(y,y0),'TailEnergy',sum(abs(tailY(:)).^2), ...
        'AggregateHistoryDifference',norm(wrongHistory-y,'fro'), ...
        'AdditionalNativeExecutions',0);
end
% A fresh component at a genuine returned-direction reset is allowed, but
% an existing component cannot be remapped through the opposite TX endpoint.
atReset=struct();
if numel(records)==7
    r=records{7}; birth=declaredBirth(r,3);
    late=sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth( ...
        r.DeclaredBinding,r.StreamBefore.Dependency,r.OriginalBeforeSnapshot,birth);
    input=.2*r.Input.Samples; input(1:3,:)=0;
    [~,expected,expectedDesired]=r.StreamBefore.advance(input,r.Input,r.Reference,r.LinkExecution);
    [~,actual,actualDesired,atReset]=late.advance(input,r.Input,r.Reference,r.LinkExecution);
    assert(isequal(actual,expected)&&isequal(actualDesired,expectedDesired) && ...
        late.ModelHistoryStartSample==late.Dependency.InputHistoryStartSample && ...
        late.ObjectTimeOffsetSamples==records{1}.Reference.ObjectTimeOffsetSamples);
end
assert(isequal(rng,beforeRNG),'test:AppliedReferenceLateBirthRNG');
result=struct('Checks',{checks},'AtActualReturnReset',atReset,'NegativeCount',negativeCount, ...
    'AdditionalNativeExecutions',0,'OriginalOwnerRegistrationQualified',false, ...
    'UpstreamRFReferenceExecuted',false,'SharedIntegrationQualified',false);
save(fullfile(folder,'late_birth_result.mat'),'result','-v7.3');
fprintf('APPLIED_CHANNEL_REFERENCE_LATE_BIRTH_PASS cases=%d negatives=%d\n',numel(checks),negativeCount);
end

function birth=declaredBirth(original,key)
first=original.Input.StartSample;
birth=struct('ContractVersion',"sixgr.rf.declared_TX_component_birth/v1", ...
    'ParentComponentID',"declared_parent_"+string(key),'ResourceID',"declared_resource", ...
    'LogicalPort',0,'ModelHistoryStartSample',first, ...
    'ComponentSupportStartSample',first+3,'ComponentSupportEndSampleExclusive',first+7, ...
    'RegistrationSHA256',string(sixgr.util.sha256Hex("declared_component_registration_"+string(key))));
end

function count=lateBirthNegatives(r,s,birth,input)
b=r.DeclaredBinding; d=r.StreamBefore.Dependency; snapshot=r.OriginalBeforeSnapshot; count=0;
bad=snapshot; bad.CurrentSampleIndex=bad.CurrentSampleIndex-1;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=snapshot; bad.TotalObjectInputSamples=bad.TotalObjectInputSamples+1;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=snapshot; bad.TotalAppliedSamples=bad.TotalAppliedSamples+1000;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=snapshot; bad.NativeSwapped=~bad.NativeSwapped;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=snapshot; bad.Direction="not_original_direction";
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=snapshot; bad.CopiedAggregateFilterState=zeros(3,2);
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,bad,birth),'History'); count=count+1;
bad=d; bad.ConfigurationEpoch=bad.ConfigurationEpoch+1;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,bad,snapshot,birth),'Dependency'); count=count+1;
bad=birth; bad.ModelHistoryStartSample=bad.ComponentSupportStartSample+1;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,snapshot,bad),'History'); count=count+1;
bad=birth; bad.ModelHistoryStartSample=flintmax;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,snapshot,bad),'History'); count=count+1;
bad=birth; bad.ComponentSupportEndSampleExclusive=bad.ComponentSupportStartSample;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,snapshot,bad),'History'); count=count+1;
bad=birth; bad.RegistrationSHA256="missing";
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,snapshot,bad),'History'); count=count+1;
bad=birth; bad.CopiedAggregateFilterState=true;
reject(@()sixgr.channel.AppliedChannelReferenceStream.fromComponentBirth(b,d,snapshot,bad),'History'); count=count+1;
bad=input; bad(1,1)=1;
reject(@()s.advance(bad,r.Input,r.Reference,r.LinkExecution),'History'); count=count+1;
bad=r.LinkExecution; bad.TX=bad.TX+"_other";
reject(@()s.advance(input,r.Input,r.Reference,bad),'Execution'); count=count+1;
bad=r.LinkExecution; bad.Replay.ChannelSignalDependency.InputHistoryStartSample=birth.ModelHistoryStartSample;
reject(@()s.advance(input,r.Input,r.Reference,bad),'History'); count=count+1;
bad=r.Reference; bad.ObjectTimeOffsetSamples=0;
reject(@()s.advance(input,r.Input,bad,r.LinkExecution),'Clock'); count=count+1;
bad=r.Reference; bad.PathGains=bad.PathGains(4:end,:,:,:);
reject(@()s.advance(input,r.Input,bad,r.LinkExecution),'Reference'); count=count+1;
badInput=sixgr.phy.waveform.WaveformChunk(input(4:end,:),r.Input.StartSample+3);
reject(@()s.advance(input(4:end,:),badInput,r.Reference,r.LinkExecution),'Input'); count=count+1;
assert(s.NextSampleIndex==birth.ModelHistoryStartSample && isequaln(s.Dependency,d));
end

function count=negatives(original)
s=original.StreamBefore; x=original.Input.Samples; input=original.Input;
r=original.Reference; e=original.LinkExecution; count=0;
bad=r; bad.PathGains(1)=bad.PathGains(1)+1;
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=r; bad.PathFilters(1)=bad.PathFilters(1)+1;
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=r; bad.PathGains=bad.PathGains(1,:,:,:);
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=r; bad.PathGains=single(bad.PathGains);
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=r; bad.SampleTimes_s=bad.SampleTimes_s+1/bad.SampleRateHz;
reject(@()s.advance(x,input,bad,e),'Clock'); count=count+1;
bad=r; bad.ObjectTimeOffsetSamples=bad.ObjectTimeOffsetSamples+1;
reject(@()s.advance(x,input,bad,e),'Clock'); count=count+1;
bad=r; bad.ExecutionStartSample=bad.StartSample-1; bad.ExecutionEndSampleExclusive=bad.EndSampleExclusive;
reject(@()s.advance(x,input,bad,e),'Clock'); count=count+1;
bad=r; bad.LargeScaleLossApplied=true;
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=r; bad.PhysicalPortMappingApplied=true;
reject(@()s.advance(x,input,bad,e),'Reference'); count=count+1;
bad=e; bad.TX=bad.TX+"_other";
reject(@()s.advance(x,input,r,bad),'Execution'); count=count+1;
bad=e; bad.Replay.ChannelSignalDependency.ConfigurationEpoch=bad.Replay.ChannelSignalDependency.ConfigurationEpoch+1;
reject(@()s.advance(x,input,r,bad),'Dependency'); count=count+1;
bad=e; bad.Replay.ChannelSignalDependency.InputHistoryStartSample=bad.Replay.ChannelSignalDependency.InputHistoryStartSample+1;
reject(@()s.advance(x,input,r,bad),'History'); count=count+1;
bad=e; bad.Replay.RuntimeChannelAppliedAlignmentTrimSamples=1;
reject(@()s.advance(x,input,r,bad),'Clock'); count=count+1;
bad=e; bad.Replay.RuntimeChannelPathGainCaptureScope="first_sample_preview";
reject(@()s.advance(x,input,r,bad),'Reference'); count=count+1;
bad=e; bad.LossReplay.AppliedLargeScaleAmplitudeGain=2*bad.LossReplay.AppliedLargeScaleAmplitudeGain;
reject(@()s.advance(x,input,r,bad),'Loss'); count=count+1;
bad=e; bad.LossReplay.PowerContextAmplitudeUnit="normalized_complex_baseband";
reject(@()s.advance(x,input,r,bad),'Loss'); count=count+1;
bad=e; bad.LossReplay.SampleRate_Hz=2*bad.LossReplay.SampleRate_Hz;
reject(@()s.advance(x,input,r,bad),'Loss'); count=count+1;
badInput=sixgr.phy.waveform.WaveformChunk(x+1,input.StartSample);
reject(@()s.advance(x,badInput,r,e),'Input'); count=count+1;
badInput=sixgr.phy.waveform.WaveformChunk(x,input.StartSample+1);
reject(@()s.advance(x,badInput,r,e),'Input'); count=count+1;
reject(@()s.advance(single(x),input,r,e),'Input'); count=count+1;
bad=e; bad.Replay.ChannelSignalDependency.Available=false;
reject(@()s.advance(x,input,r,bad),'Dependency'); count=count+1;
% Successful use returns a new value; replaying that original interval in
% the advanced stream cannot masquerade as new input or reset history.
[advanced,~,~,~]=s.advance(x,input,r,e);
reject(@()advanced.advance(x,input,r,e),'Input'); count=count+1;
assert(s.NextSampleIndex==input.StartSample);
% Original native gains are independently bound by the execution digest.
% The two scalar flags have no independent copy in the current dependency
% or replay. Never claim these first-record labels are verified or use them
% to rescale the already-applied gains.
bad=r; bad.NormalizeChannelOutputs=~bad.NormalizeChannelOutputs;
[~,sameNumeric,~,flagReceipt]=s.advance(x,input,bad,e);
assert(isequal(sameNumeric,original.PredictedNative)&&~flagReceipt.NormalizationFlagsVerified && ...
    flagReceipt.NormalizationFlagsAuthority=="unverified_reference_metadata_not_used_for_scaling" && ...
    ~flagReceipt.AdditionalNormalizationApplied);
end

function b=makeBinding(direction,epoch)
if direction=="DL", tx="gnb"; rx="ue_rx"; else, tx="ue"; rx="gnb_rx"; end
b=struct('LinkID',"declared_native_link",'TX',tx,'RX',rx, ...
    'ConfigurationEpoch',epoch,'WaveformAmplitudeUnit',"sqrt_mW");
end
function x=signal(n,ports,key)
x=.01*exp(1i*((0:n-1).'*(1:ports)/19+key*(1:ports)/7));
end
function r=relative(a,b)
r=norm(a-b,'fro')/max(realmin,norm(b,'fro'));
end
function reject(fn,suffix)
expected="sixgr:channel:AppliedReference"+suffix;
try, fn(); catch cause
    assert(string(cause.identifier)==expected,'test:AppliedReferenceWrongRejection', ...
        'Expected %s; got %s: %s',expected,cause.identifier,cause.message); return;
end
error('test:AppliedReferenceMissingRejection','Expected %s.',expected);
end
