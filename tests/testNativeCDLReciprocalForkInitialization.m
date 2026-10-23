function ok=testNativeCDLReciprocalForkInitialization(includeLarge)
% Public-API candidate probe, NOT a production fix or a decoded-PHY test.
% R2026a clone/save of an unused reciprocal comm.ChannelFilter loses its
% private stopband setting. Retain that counterexample independently of the
% fresh-only initialization candidate. Never reset an already live owner.
if nargin<1, includeLarge=false; end
setup6GRSimToolkit('Verbose',false);
assert(exist('nrCDLChannel','class')==8,'test:NativeCDLRequired', ...
    'This native component cannot qualify without nrCDLChannel.');
parent=fullfile(pwd,'logs','native_cdl_reciprocal_fork_initialization');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('NATIVE_CDL_FORK_INITIALIZATION_AUDIT %s\n',folder);
initialRNG=rng;
cases={caseSpec("inf_start_DL",Inf,"DL",4,2,256,false), ...
    caseSpec("inf_start_UL",Inf,"UL",4,2,256,false), ...
    caseSpec("finite_interpolated_start_DL",4,"DL",4,2,256,false), ...
    caseSpec("finite_interpolated_start_UL",4,"UL",4,2,256,false), ...
    caseSpec("finite_batch_start_DL",4,"DL",4,2,1,true), ...
    caseSpec("finite_batch_start_UL",4,"UL",4,2,1,true)};
if includeLarge
    cases{end+1}=caseSpec("inf_64_4_start_DL",Inf,"DL",64,4,256,false);
end
results=cell(size(cases)); failures=struct('Case',{},'Identifier',{},'Report',{});
for c=1:numel(cases)
    try
        results{c}=runCase(cases{c});
    catch cause
        failures(end+1)=struct('Case',cases{c}.Name,'Identifier',string(cause.identifier), ...
            'Report',string(getReport(cause,'extended','hyperlinks','off'))); %#ok<AGROW>
        fprintf('NATIVE_CDL_FORK_INITIALIZATION_CASE_FAIL %s %s\n',cases{c}.Name,cause.identifier);
    end
end
finalRNG=rng; nativeVersion=ver('5g'); release=version('-release');
nativeSource=which('nrCDLChannel'); nativeSourceSHA256=sixgr.util.sha256File(nativeSource);
save(fullfile(folder,'summary.mat'),'cases','results','failures','initialRNG','finalRNG', ...
    'nativeVersion','release','nativeSource','nativeSourceSHA256','-v7.3');
assert(isequal(initialRNG,finalRNG),'test:NativeCDLGlobalRNGChanged', ...
    'Seeded native setup, cloning and restoration must not change global RNG.');
assert(isempty(failures),'test:NativeCDLFreshInitializationUnqualified', ...
    'Fresh-only public initialization candidate failed %d case(s); retain the audit, not a production qualification.',numel(failures));
fprintf('NATIVE_CDL_FORK_INITIALIZATION_PASS cases=%d exact_samples=1 fresh_only=1 production_wired=0 decoded_PHY=0\n',numel(cases));
ok=true;

    function result=runCase(spec)
        caseFolder=fullfile(folder,char(spec.Name)); mkdir(caseFolder);
        save(fullfile(caseFolder,'declared_case.mat'),'spec','-v7.3');
        baseline=makeNative(spec); candidate=makeNative(spec);
        assert(~isLocked(baseline)&&~isLocked(candidate));
        nInput=spec.Tx; nReverse=spec.Rx;
        if spec.Direction=="UL", nInput=spec.Rx; nReverse=spec.Tx; end
        zerosInitial=complex(zeros(spec.InitialLength,nInput));
        rngBefore=rng;
        % Only the fresh candidate is initialized. The untouched baseline
        % receives precisely the ordinary warmup and physical input series.
        executeRecorded(candidate,zerosInitial,'fresh_setup','candidate');
        if isfinite(spec.Density)
            executeRecorded(candidate,complex(zeros(8192,nInput)),'fresh_long','candidate');
        end
        beforeSwap=matlab.System.saveObject(candidate);
        swapTransmitAndReceive(candidate);
        executeRecorded(candidate,complex(zeros(256,nReverse)),'fresh_reverse','candidate');
        swapTransmitAndReceive(candidate);
        % Public reset retains initialized native filters while restoring
        % this fresh candidate's initial seed/time/Doppler/filter state.
        reset(candidate);
        primed=matlab.System.saveObject(candidate);
        save(fullfile(caseFolder,'fresh_initialization.mat'),'spec','beforeSwap','primed','rngBefore','-v7.3');
        assert(isequal(rngBefore,rng),'test:NativeCDLGlobalRNGChanged');
        observations={}; checks=struct('Phase',{},'Subject',{},'SamplesEqual',{}, ...
            'GainsEqual',{},'TimesEqual',{},'MaxAbsoluteSampleDifference',{});
        samplesConsumed=0;
        compareInitial('ordinary_warmup',zerosInitial);
        compareInitial('prefix_nonzero',stimulus(37,nInput,1));
        compareInitial('prefix_tail',complex(zeros(128,nInput)));
        forkOriginSamples=samplesConsumed;
        oldFork=clone(baseline);
        candidateFork=clone(candidate);
        checkpoint=candidate;
        checkpointPath=fullfile(caseFolder,'original_checkpoint.mat');
        save(checkpointPath,'checkpoint','-v7.3');
        loaded=load(checkpointPath,'checkpoint'); restored=loaded.checkpoint;
        liveBeforeFork=matlab.System.saveObject(baseline);
        candidateBeforeFork=matlab.System.saveObject(candidate);
        save(fullfile(caseFolder,'fork_origin.mat'),'liveBeforeFork','candidateBeforeFork', ...
            'forkOriginSamples','-v7.3');
        longLength=73; if isfinite(spec.Density), longLength=8192; end
        compareAll('same_direction_continuation',stimulus(longLength,nInput,2));
        beforeReverse=matlab.System.saveObject(baseline);
        candidateBeforeReverse=matlab.System.saveObject(candidate);
        compareAll('outgoing_tail',complex(zeros(128,nInput)));
        swapAll();
        compareAll('reverse_direction',stimulus(41,nReverse,3));
        if isfinite(spec.Density)
            compareAll('reverse_long_sections',stimulus(8192,nReverse,5));
        end
        compareAll('reverse_tail',complex(zeros(128,nReverse)));
        swapAll();
        compareAll('return_direction',stimulus(23,nInput,4));
        states=struct('Baseline',matlab.System.saveObject(baseline), ...
            'OldFork',matlab.System.saveObject(oldFork), ...
            'Candidate',matlab.System.saveObject(candidate), ...
            'CandidateFork',matlab.System.saveObject(candidateFork), ...
            'Restored',matlab.System.saveObject(restored));
        result=struct('Spec',spec,'Checks',checks,'Observations',{observations}, ...
            'ForkOriginSamples',forkOriginSamples,'SamplesConsumed',samplesConsumed, ...
            'BeforeReverse',beforeReverse,'CandidateBeforeReverse',candidateBeforeReverse, ...
            'FinalStates',states,'RNGUnchanged',isequal(rngBefore,rng), ...
            'SourceScope',"declared_native_channel_component_public_initialization_candidate", ...
            'ProductionWired',false,'DecodedPHY',false);
        % Preserve all numeric outputs and serialized state before checks.
        save(fullfile(caseFolder,'original_comparisons.mat'),'result','-v7.3');
        oldMask=string({checks.Subject})=="unprimed_clone_counterexample";
        selected=checks(~oldMask);
        assert(all([selected.SamplesEqual])&&all([selected.GainsEqual])&&all([selected.TimesEqual]), ...
            'test:NativeCDLFreshInitializationMismatch', ...
            'Candidate/original/fork/checkpoint must exactly match untouched native execution.');
        assert(any(~[checks(oldMask).SamplesEqual])&&all([checks(oldMask).GainsEqual])&& ...
            all([checks(oldMask).TimesEqual]),'test:NativeCDLCounterexampleNotIsolated', ...
            'The old native clone counterexample must be separate from fading/clock changes.');
        % Read-only pinned-native diagnostics. No private field is changed.
        a=states.Baseline.ChildClassData; b=states.Candidate.ChildClassData;
        assert(isequal(a.theTime,b.theTime)&&result.RNGUnchanged, ...
            'test:NativeCDLClockOrRNGChanged');
        if spec.RequireBatch
            assert(filterLocked(beforeSwap,'channelFilterBatch')&& ...
                filterLocked(beforeReverse,'channelFilterBatch'), ...
                'test:NativeCDLBatchPathUnexercised', ...
                'Finite density is not qualified unless actual native batch filtering ran.');
            assert(~isempty(beforeSwap.ChildClassData.filterContinuity.nSections)&& ...
                ~isempty(beforeReverse.ChildClassData.filterContinuity.nSections), ...
                'test:NativeCDLBatchContinuityUnexercised');
        elseif isfinite(spec.Density)
            currentFilter='channelFilter';
            if spec.Direction=="UL", currentFilter='channelFilterReciprocal'; end
            assert(~beforeReverse.ChildClassData.(currentFilter).ChildClassData.OptimizeScalarGainFilter&& ...
                ~filterLocked(beforeReverse,'channelFilterBatch'), ...
                'test:NativeCDLInterpolationPathUnexercised');
        end
        fprintf('NATIVE_CDL_FORK_INITIALIZATION_CASE_PASS %s old_clone_mismatch=1 samples=%d batch_exercised=%d\n', ...
            spec.Name,samplesConsumed,spec.RequireBatch);

        function compareInitial(phase,x)
            base=executeRecorded(baseline,x,phase,'baseline');
            proposed=executeRecorded(candidate,x,phase,'candidate');
            observations{end+1}=struct('Phase',string(phase),'Input',x,'Baseline',base,'Candidate',proposed);
            compare(phase,'fresh_initialized_original',base,proposed);
            samplesConsumed=samplesConsumed+size(x,1);
        end
        function compareAll(phase,x)
            base=executeRecorded(baseline,x,phase,'baseline');
            old=executeRecorded(oldFork,x,phase,'old_clone');
            proposed=executeRecorded(candidate,x,phase,'candidate');
            forked=executeRecorded(candidateFork,x,phase,'candidate_clone');
            saved=executeRecorded(restored,x,phase,'candidate_checkpoint');
            observations{end+1}=struct('Phase',string(phase),'Input',x,'Baseline',base, ...
                'OldFork',old,'Candidate',proposed,'CandidateFork',forked,'Restored',saved);
            compare(phase,'unprimed_clone_counterexample',base,old);
            compare(phase,'fresh_initialized_original',base,proposed);
            compare(phase,'fresh_initialized_clone',base,forked);
            compare(phase,'fresh_initialized_checkpoint',base,saved);
            samplesConsumed=samplesConsumed+size(x,1);
        end
        function compare(phase,subject,left,right)
            delta=abs(left.Samples-right.Samples);
            checks(end+1)=struct('Phase',string(phase),'Subject',string(subject), ...
                'SamplesEqual',isequaln(left.Samples,right.Samples), ...
                'GainsEqual',isequaln(left.PathGains,right.PathGains), ...
                'TimesEqual',isequaln(left.SampleTimes,right.SampleTimes), ...
                'MaxAbsoluteSampleDifference',max(delta,[],'all'));
        end
        function swapAll()
            swapTransmitAndReceive(baseline); swapTransmitAndReceive(oldFork);
            swapTransmitAndReceive(candidate); swapTransmitAndReceive(candidateFork);
            swapTransmitAndReceive(restored);
        end
        function out=executeRecorded(owner,x,phase,subject)
            % Save pre-call value snapshots first, then the exact successful
            % output immediately. A later native error must not erase it.
            before=matlab.System.saveObject(owner); rngAtCall=rng;
            stem=fullfile(caseFolder,[char(phase) '_' char(subject)]);
            save([stem '_before.mat'],'before','x','rngAtCall','-v7.3');
            out=execute(owner,x);
            after=matlab.System.saveObject(owner); rngAfterCall=rng;
            save([stem '_after.mat'],'out','after','rngAfterCall','-v7.3');
        end
    end
end

function spec=caseSpec(name,density,direction,tx,rx,initialLength,requireBatch)
spec=struct('Name',name,'Density',density,'Direction',direction,'Tx',tx,'Rx',rx, ...
    'InitialLength',initialLength,'RequireBatch',requireBatch);
end

function c=makeNative(spec)
c=nrCDLChannel;
c.DelayProfile='CDL-C'; c.DelaySpread=100e-9;
c.CarrierFrequency=2.35e9; c.SampleRate=7.68e6;
c.MaximumDopplerShift=2000; c.SampleDensity=spec.Density;
c.NormalizePathGains=false; c.NormalizeChannelOutputs=false;
c.RandomStream='mt19937ar with seed'; c.Seed=65537;
c.InitialTime=0.003125;
c.ChannelFiltering=true; c.ChannelResponseOutput='path-gains';
tx=c.TransmitAntennaArray; tx.Size=[spec.Tx/2 1 2 1 1]; c.TransmitAntennaArray=tx;
rx=c.ReceiveAntennaArray; rx.Size=[spec.Rx/2 1 2 1 1]; c.ReceiveAntennaArray=rx;
if spec.Direction=="UL", swapTransmitAndReceive(c); end
end
function result=execute(c,x)
[y,g,t]=c(x);
result=struct('Samples',y,'PathGains',g,'SampleTimes',t);
end
function x=stimulus(n,ports,key)
t=(0:n-1).'; p=1:ports;
x=.01*exp(1i*(t*p/19+key*p/7));
end
function value=filterLocked(snapshot,name)
filter=snapshot.ChildClassData.(name);
value=isfield(filter,'SuperClassData')&&isfield(filter.SuperClassData,'Locked')&& ...
    isequal(filter.SuperClassData.Locked,true);
end
