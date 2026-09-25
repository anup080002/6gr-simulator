classdef WaveformStreamComposer < handle
    %WAVEFORMSTREAMCOMPOSER Physical-antenna samples on one absolute clock.
    % Inputs must already have the same sample rate, frequency reference,
    % power reference, and physical antenna mapping. This is not a channel
    % or a resampler. Callers must enqueue all scheduled contributors before
    % consuming a window; consumed samples cannot be revised retroactively.
    properties (SetAccess=private)
        SampleRateHz (1,1) double
        NumTransmitAntennas (1,1) double
        NextSampleIndex (1,1) double
    end
    properties (Access=private)
        Pending = cell(0,1)
        PendingComponentIDs = strings(0,1)
        ComponentIDs = strings(0,1)
        SampleClass (1,1) string = ""
    end
    methods
        function obj=WaveformStreamComposer(sampleRateHz,numTransmitAntennas,startSample)
            validateattributes(sampleRateHz,{'numeric'}, ...
                {'real','scalar','finite','positive'});
            validateattributes(numTransmitAntennas,{'numeric'}, ...
                {'real','scalar','finite','integer','positive'});
            validateattributes(startSample,{'numeric'}, ...
                {'real','scalar','finite','integer','nonnegative'});
            obj.SampleRateHz=double(sampleRateHz);
            obj.NumTransmitAntennas=double(numTransmitAntennas);
            obj.NextSampleIndex=double(startSample);
        end

        function declareSamplePrecision(obj,precision)
            % An idle physical transmitter emits zeros; declaring its type
            % does not fabricate a transmitted component or an RX sample.
            precision=string(precision);
            if ~isscalar(precision) || ismissing(precision) || ~any(precision==["single","double"])
                error("WAVEFORM:InvalidSamplePrecision","Declare single or double samples.");
            end
            if obj.SampleClass~="" && obj.SampleClass~=precision
                error("WAVEFORM:SamplePrecisionMismatch","Cannot change a materialized stream's precision.");
            end
            obj.SampleClass=precision;
        end

        function enqueue(obj,componentID,chunk,sampleRateHz)
            id=string(componentID);
            if ~isscalar(id)||ismissing(id)||strlength(strtrim(id))==0
                error("WAVEFORM:InvalidComponentID","A waveform component needs one explicit identity.");
            end
            if any(obj.ComponentIDs==id)
                error("WAVEFORM:DuplicateComponent","Component %s was already submitted.",id);
            end
            if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk')||~isscalar(chunk)
                error("WAVEFORM:InvalidChunk","Submit one materialized WaveformChunk.");
            end
            if ~isnumeric(sampleRateHz)||~isreal(sampleRateHz)|| ...
                    ~isscalar(sampleRateHz)||~isfinite(sampleRateHz)|| ...
                    double(sampleRateHz)~=obj.SampleRateHz
                error("WAVEFORM:SampleRateMismatch", ...
                    "Components must be materialized on the stream's common sample clock.");
            end
            samples=chunk.Samples;
            if ~(isa(samples,'double')||isa(samples,'single'))|| ...
                    ~ismatrix(samples)||isempty(samples)|| ...
                    size(samples,2)~=obj.NumTransmitAntennas|| ...
                    any(~isfinite(samples(:)))
                error("WAVEFORM:InvalidPhysicalSamples", ...
                    "Samples must be finite, nonempty, and mapped to every physical TX antenna.");
            end
            start=chunk.StartSample;
            if ~isscalar(start)||~isreal(start)||~isfinite(start)|| ...
                    start<0||start~=fix(start)
                error("WAVEFORM:InvalidSampleOrigin","Chunk origin must be a nonnegative integer.");
            end
            if start<obj.NextSampleIndex
                error("WAVEFORM:LateComponent", ...
                    "Component %s starts at sample %.0f, before consumed boundary %.0f.", ...
                    id,start,obj.NextSampleIndex);
            end
            if obj.SampleClass~="" && obj.SampleClass~=string(class(samples))
                error("WAVEFORM:SamplePrecisionMismatch", ...
                    "Stream components must use one explicit sample precision.");
            end
            obj.SampleClass=string(class(samples));
            obj.Pending{end+1,1}=chunk;
            obj.PendingComponentIDs(end+1,1)=id;
            obj.ComponentIDs(end+1,1)=id;
        end

        function receipt=cancelUnemittedComponent(obj,componentID)
            % UE priority can suppress a queued waveform after its all-zero
            % prefix passed, but never after ANY nonzero sample was emitted.
            id=string(componentID);
            hit=find(obj.PendingComponentIDs==id);
            assert(isscalar(id) && isscalar(hit), ...
                'WAVEFORM:UnknownPendingComponent','Cancel one exact pending component.');
            chunk=obj.Pending{hit};
            consumed=max(0,min(size(chunk.Samples,1),obj.NextSampleIndex-chunk.StartSample));
            assert(~any(chunk.Samples(1:consumed,:)~=0,'all'), ...
                'WAVEFORM:CannotCancelEmittedComponent', ...
                'Consumed nonzero samples cannot be cancelled, subtracted or rewritten.');
            receipt=struct('ComponentID',id,'CancelledAtSample',obj.NextSampleIndex, ...
                'OriginalStartSample',chunk.StartSample,'OriginalEndSampleExclusive',chunk.EndSample+1, ...
                'OriginalSampleSHA256',chunk.SHA256,'ConsumedPrefixSamples',consumed, ...
                'EmittedNonzeroSamples',0,'PreviouslyConsumedSamplesChanged',false);
            obj.Pending(hit)=[]; obj.PendingComponentIDs(hit)=[];
            % Keep ComponentIDs: cancellation does not permit identity reuse.
        end

        function chunk=readThrough(obj,endSampleExclusive)
            % Half-open [NextSampleIndex,endSampleExclusive) consumption.
            validateattributes(endSampleExclusive,{'numeric'}, ...
                {'real','scalar','finite','integer','nonnegative'});
            stop=double(endSampleExclusive);
            if stop<obj.NextSampleIndex
                error("WAVEFORM:StreamTimeReversal","A consumed stream cannot move backwards.");
            end
            if obj.SampleClass==""
                error("WAVEFORM:UnmaterializedStream", ...
                    "Materialize at least one component before consuming the stream.");
            end
            first=obj.NextSampleIndex;
            samples=complex(zeros(stop-first,obj.NumTransmitAntennas,char(obj.SampleClass)));
            keep=true(numel(obj.Pending),1);
            for k=1:numel(obj.Pending)
                component=obj.Pending{k};
                componentEnd=component.StartSample+size(component.Samples,1);
                lo=max(first,component.StartSample);
                hi=min(stop,componentEnd);
                if hi>lo
                    dst=(lo-first+1):(hi-first);
                    src=(lo-component.StartSample+1):(hi-component.StartSample);
                    samples(dst,:)=samples(dst,:)+component.Samples(src,:);
                end
                keep(k)=componentEnd>stop;
            end
            % Create the immutable output before committing cursor/queue state.
            chunk=sixgr.phy.waveform.WaveformChunk(samples,first);
            obj.Pending=obj.Pending(keep);
            obj.PendingComponentIDs=obj.PendingComponentIDs(keep);
            obj.NextSampleIndex=stop;
        end
    end
    methods (Static)
        function [chunk,state]=frequencyShift(samples,frequencyHz,sampleRateHz,state)
            start=state.NextSampleIndex;
            [samples,state]=sixgr.phy.waveform.DigitalUpconverter.process( ...
                samples,frequencyHz,sampleRateHz,state);
            chunk=sixgr.phy.waveform.WaveformChunk(samples,start);
        end
    end
end
