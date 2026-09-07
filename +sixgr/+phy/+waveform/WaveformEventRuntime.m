classdef WaveformEventRuntime < handle
    % Chronological composition and RX dispatch, with physical processing
    % delegated ONCE per interval to the retained node/link/RF owner.
    % No propagation, noise, power, duplex or scheduling policy is invented
    % here. The processor receives every node's already summed antenna
    % samples and must return every declared observation plane.
    % advanceUntilEvent stops at the earliest completed receiver window or
    % explicit decision boundary. A caller must react before advancing again.
    properties (SetAccess=private)
        SampleRateHz (1,1) double
        NextSampleIndex (1,1) double
        Faulted (1,1) logical = false
        FailureIdentifier (1,1) string = ""
        ProcessorState
        ExecutionTrace = cell(0,1)
    end
    properties (Access=private)
        Processor
        Busy (1,1) logical = false
        Transmitters = struct('ID',{},'Composer',{},'CommittedThroughSample',{})
        Receivers = struct('ID',{},'Dispatcher',{})
        Windows = struct('ReceiverID',{},'ID',{},'Start',{},'Stop',{},'Segments',{})
        Boundaries = struct('ID',{},'Sample',{})
        BoundaryIDs = strings(0,1)
    end
    methods
        function obj=WaveformEventRuntime(fs,first,processor,processorState)
            validateattributes(fs,{'numeric'},{'real','scalar','finite','positive'});
            validateattributes(first,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            if ~isa(processor,'function_handle') || ~isscalar(processor)
                error('WAVEFORM:MissingPhysicalProcessor','One retained physical processor is required.');
            end
            obj.SampleRateHz=double(fs); obj.NextSampleIndex=double(first);
            obj.Processor=processor; obj.ProcessorState=processorState;
        end

        function addTransmitter(obj,id,numAntennas,precision)
            obj.assertMutable(); id=obj.validID(id);
            if any(string({obj.Transmitters.ID})==id)
                error('WAVEFORM:DuplicateTransmitter','Transmitter %s already exists.',id);
            end
            composer=sixgr.phy.waveform.WaveformStreamComposer( ...
                obj.SampleRateHz,numAntennas,obj.NextSampleIndex);
            composer.declareSamplePrecision(precision);
            obj.Transmitters(end+1)=struct('ID',id,'Composer',composer, ...
                'CommittedThroughSample',obj.NextSampleIndex);
        end

        function addReceiver(obj,id,numAntennas)
            % Separate pre-RF, post-RF and TX observation planes have their
            % own explicit IDs and dimensions, even when owned by one node.
            obj.assertMutable(); id=obj.validID(id);
            if any(string({obj.Receivers.ID})==id)
                error('WAVEFORM:DuplicateReceiver','Receiver plane %s already exists.',id);
            end
            dispatcher=sixgr.phy.waveform.WaveformReceiveDispatcher( ...
                obj.SampleRateHz,numAntennas,obj.NextSampleIndex);
            obj.Receivers(end+1)=struct('ID',id,'Dispatcher',dispatcher);
        end

        function enqueue(obj,transmitterID,componentID,chunk)
            obj.assertMutable();
            k=obj.findID(obj.Transmitters,transmitterID,'Transmitter');
            if isa(chunk,'sixgr.phy.waveform.WaveformChunk') && isscalar(chunk) && ...
                    any(chunk.StartSample<obj.Transmitters(k).CommittedThroughSample)
                error('WAVEFORM:CommittedTransmission', ...
                    'A committed transmitter interval cannot acquire another component.');
            end
            obj.Transmitters(k).Composer.enqueue(componentID,chunk,obj.SampleRateHz);
        end

        function commitTransmissionsThrough(obj,transmitterID,stop)
            % The scheduler certifies that this node's contributors (or
            % intentional silence) are fully known through this boundary.
            % Precision declaration alone is NOT permission to fill an
            % unknown future schedule with zeros.
            obj.assertMutable();
            k=obj.findID(obj.Transmitters,transmitterID,'Transmitter');
            validateattributes(stop,{'numeric'},{'real','scalar','finite','integer', ...
                '>=',obj.Transmitters(k).CommittedThroughSample});
            obj.Transmitters(k).CommittedThroughSample=double(stop);
        end

        function observe(obj,receiverID,id,first,stop)
            obj.assertMutable(); id=obj.validID(id);
            k=obj.findID(obj.Receivers,receiverID,'Receiver');
            obj.Receivers(k).Dispatcher.register(id,first,stop);
            obj.Windows(end+1)=struct('ReceiverID',string(receiverID),'ID',id, ...
                'Start',double(first),'Stop',double(stop),'Segments',{{}});
        end

        function decisionBoundary(obj,id,sample)
            obj.assertMutable(); id=obj.validID(id);
            validateattributes(sample,{'numeric'},{'real','scalar','finite','integer','>=',obj.NextSampleIndex});
            if any(obj.BoundaryIDs==id)
                error('WAVEFORM:DuplicateDecisionBoundary','Boundary %s already exists.',id);
            end
            obj.Boundaries(end+1)=struct('ID',id,'Sample',double(sample));
            obj.BoundaryIDs(end+1,1)=id;
        end

        function event=advanceUntilEvent(obj,requestedStop)
            obj.assertMutable();
            validateattributes(requestedStop,{'numeric'},{'real','scalar','finite','integer','>=',obj.NextSampleIndex});
            if isempty(obj.Transmitters) || isempty(obj.Receivers)
                error('WAVEFORM:UnconfiguredEventRuntime','Register physical transmitters and observation planes first.');
            end
            first=obj.NextSampleIndex;
            stop=min([double(requestedStop),[obj.Windows.Stop],[obj.Boundaries.Sample]]);
            event=struct('StartSample',first,'EndSampleExclusive',stop, ...
                'RequestedStopSample',double(requestedStop),'Decisions',strings(0,1), ...
                'Completed',struct('ReceiverID',{},'ID',{},'Observation',{},'Segments',{}), ...
                'Execution',struct(),'PhysicalExecutionPerformed',false);
            if stop==first
                % A scheduled action may be due exactly at the current
                % sample. Deliver it once without consuming future samples.
                hit=[obj.Boundaries.Sample]==first;
                event.Decisions=string({obj.Boundaries(hit).ID}).';
                obj.Boundaries=obj.Boundaries(~hit);
                return;
            end
            if any([obj.Transmitters.CommittedThroughSample]<stop)
                error('WAVEFORM:UncommittedTransmissionInterval', ...
                    'Every physical transmitter must commit its complete schedule through sample %.0f.',stop);
            end
            obj.Busy=true;
            unlock=onCleanup(@()obj.clearBusy()); %#ok<NASGU>
            try
                inputs=struct('ID',{},'Chunk',{});
                for k=1:numel(obj.Transmitters)
                    node=obj.Transmitters(k);
                    inputs(end+1)=struct('ID',node.ID,'Chunk',node.Composer.readThrough(stop)); %#ok<AGROW>
                end
                % A physical exception may have advanced mutable channel or
                % oscillator handles. There is no safe automatic retry or
                % hidden channel clone/rollback; poison this runtime below.
                [outputs,execution,nextState]=obj.Processor( ...
                    inputs,first,stop,obj.ProcessorState);
                obj.validateOutputs(outputs,execution,first,stop);
                segment=struct('StartSample',first,'EndSampleExclusive',stop, ...
                    'Execution',execution);
                for k=1:numel(obj.Windows)
                    w=obj.Windows(k);
                    if w.Start<stop && w.Stop>first
                        obj.Windows(k).Segments{end+1}=segment;
                    end
                end
                for k=1:numel(obj.Receivers)
                    plane=obj.Receivers(k);
                    index=find(string({outputs.ID})==plane.ID,1);
                    done=plane.Dispatcher.dispatch(outputs(index).Chunk,obj.SampleRateHz);
                    for j=1:numel(done)
                        index=find(string({obj.Windows.ReceiverID})==plane.ID & ...
                            string({obj.Windows.ID})==done(j).ID,1);
                        event.Completed(end+1)=struct('ReceiverID',plane.ID,'ID',done(j).ID, ...
                            'Observation',done(j).Observation,'Segments',{obj.Windows(index).Segments}); %#ok<AGROW>
                    end
                end
                obj.Windows=obj.Windows([obj.Windows.Stop]>stop);
                hit=[obj.Boundaries.Sample]==stop;
                event.Decisions=string({obj.Boundaries(hit).ID}).';
                obj.Boundaries=obj.Boundaries(~hit);
                obj.ProcessorState=nextState;
                obj.ExecutionTrace{end+1,1}=segment;
                obj.NextSampleIndex=stop;
                event.Execution=execution;
                event.PhysicalExecutionPerformed=true;
            catch cause
                obj.Faulted=true;
                obj.FailureIdentifier=string(cause.identifier);
                rethrow(cause);
            end
        end
    end
    methods (Access=private)
        function assertMutable(obj)
            if obj.Faulted
                error('WAVEFORM:FaultedEventRuntime', ...
                    'Physical processing failed (%s); this possibly advanced runtime cannot be retried.',obj.FailureIdentifier);
            end
            if obj.Busy
                error('WAVEFORM:ReentrantEventRuntime','Physical processing cannot reschedule its own active interval.');
            end
        end

        function clearBusy(obj), obj.Busy=false; end

        function validateOutputs(obj,outputs,execution,first,stop)
            if ~isstruct(outputs) || numel(outputs)~=numel(obj.Receivers) || ...
                    ~all(isfield(outputs,{'ID','Chunk'}))
                error('WAVEFORM:IncompletePhysicalOutputs','Return exactly one chunk for each declared receiver plane.');
            end
            ids=string({outputs.ID}); expected=string({obj.Receivers.ID});
            if numel(ids)~=numel(unique(ids)) || ~isequal(sort(ids),sort(expected))
                error('WAVEFORM:IncompletePhysicalOutputs','Physical output identities differ from registered planes.');
            end
            if ~isstruct(execution) || ~isscalar(execution) || ...
                    ~all(isfield(execution,{'Source','ApproximationMode','StartSample','EndSampleExclusive'})) || ...
                    ~isequal(execution.StartSample,first) || ~isequal(execution.EndSampleExclusive,stop)
                error('WAVEFORM:PhysicalExecutionClockMismatch','Execution evidence must cover exactly the consumed interval.');
            end
            source=string(execution.Source); approximation=string(execution.ApproximationMode);
            if ~isscalar(source) || ismissing(source) || strlength(strtrim(source))==0 || ...
                    ~isscalar(approximation) || ismissing(approximation) || ...
                    ~any(approximation==["none","exact"])
                error('WAVEFORM:ProxyPhysicalExecutionForbidden','Physical stream evidence requires its explicit source and no approximation.');
            end
            if ~isempty(regexp(lower(char(source)), ...
                    'proxy|fallback|synthetic|logistic|(^|[^a-z])lut($|[^a-z])','once'))
                error('WAVEFORM:ProxyPhysicalExecutionForbidden', ...
                    'An approximation source cannot be relabeled as physical execution.');
            end
            names=string(fieldnames(execution));
            flags=names(startsWith(lower(names),["proxyused","fallbackused","syntheticused"]));
            for flag=flags(:).'
                if ~isequal(execution.(flag),false) && ~isequal(execution.(flag),0)
                    error('WAVEFORM:ProxyPhysicalExecutionForbidden', ...
                        'Physical execution contradicts its no-approximation declaration: %s.',flag);
                end
            end
            for k=1:numel(obj.Receivers)
                i=find(ids==expected(k),1); chunk=outputs(i).Chunk;
                if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk') || ~isscalar(chunk)
                    error('WAVEFORM:InvalidPhysicalOutputChunk','Physical output requires an immutable WaveformChunk.');
                end
                x=chunk.Samples;
                if ~isfloat(x) || ~ismatrix(x) || size(x,1)~=stop-first || ...
                        size(x,2)~=obj.Receivers(k).Dispatcher.NumReceiveAntennas || ...
                        any(~isfinite(x(:))) || ~isequal(chunk.StartSample,first)
                    error('WAVEFORM:PhysicalOutputIntervalMismatch','Actual output samples must match clock, coverage and antenna dimensions.');
                end
            end
        end
    end
    methods (Static,Access=private)
        function id=validID(id)
            id=string(id);
            if ~isscalar(id) || ismissing(id) || strlength(strtrim(id))==0
                error('WAVEFORM:InvalidRuntimeID','An explicit scalar identity is required.');
            end
        end
        function index=findID(items,id,kind)
            id=sixgr.phy.waveform.WaveformEventRuntime.validID(id);
            index=find(string({items.ID})==id,1);
            if isempty(index)
                error('WAVEFORM:UnknownRuntimeEndpoint','Unknown %s %s.',kind,id);
            end
        end
    end
end
