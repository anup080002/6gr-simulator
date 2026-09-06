classdef WaveformReceiveDispatcher < handle
    %WAVEFORMRECEIVEDISPATCHER Route one chronological RX stream to its windows.
    % The caller owns physical channel/RF execution. Dispatch only its actual
    % received samples; this class neither generates samples nor pads gaps.
    properties (SetAccess=private)
        SampleRateHz (1,1) double
        NumReceiveAntennas (1,1) double
        NextSampleIndex (1,1) double
    end
    properties (Access=private)
        Pending = cell(0,1)
        PendingIDs = strings(0,1)
        RegisteredIDs = strings(0,1)
        SampleClass (1,1) string = ""
    end
    methods
        function obj=WaveformReceiveDispatcher(sampleRateHz,numRx,startSample)
            validateattributes(sampleRateHz,{'numeric'},{'real','scalar','finite','positive'});
            validateattributes(numRx,{'numeric'},{'real','scalar','finite','integer','positive'});
            validateattributes(startSample,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
            obj.SampleRateHz=double(sampleRateHz);
            obj.NumReceiveAntennas=double(numRx);
            obj.NextSampleIndex=double(startSample);
        end

        function register(obj,id,startSample,endSampleExclusive)
            id=string(id);
            if ~isscalar(id)||ismissing(id)||strlength(strtrim(id))==0
                error("WAVEFORM:InvalidObservationID","An observation requires an explicit scalar identity.");
            end
            if any(obj.RegisteredIDs==id)
                error("WAVEFORM:DuplicateObservation","Observation %s was already registered.",id);
            end
            buffer=sixgr.phy.waveform.WaveformObservationBuffer( ...
                startSample,endSampleExclusive,obj.SampleRateHz,obj.NumReceiveAntennas);
            if buffer.StartSample<obj.NextSampleIndex
                error("WAVEFORM:LateObservation", ...
                    "Observation %s starts before the received stream boundary %.0f.",id,obj.NextSampleIndex);
            end
            obj.Pending{end+1,1}=buffer;
            obj.PendingIDs(end+1,1)=id;
            obj.RegisteredIDs(end+1,1)=id;
        end

        function completed=dispatch(obj,chunk,sampleRateHz)
            if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk')||~isscalar(chunk)
                error("WAVEFORM:InvalidObservationChunk","Dispatch one received WaveformChunk.");
            end
            if ~isnumeric(sampleRateHz)||~isreal(sampleRateHz)|| ...
                    ~isscalar(sampleRateHz)||~isfinite(sampleRateHz)||sampleRateHz~=obj.SampleRateHz
                error("WAVEFORM:ObservationSampleRateMismatch","Received samples must retain the stream sample rate.");
            end
            if chunk.StartSample~=obj.NextSampleIndex
                error("WAVEFORM:ObservationDiscontinuity", ...
                    "Expected received sample %.0f; got %.0f.",obj.NextSampleIndex,chunk.StartSample);
            end
            x=chunk.Samples;
            if ~(isa(x,'single')||isa(x,'double'))||~ismatrix(x)||isempty(x)|| ...
                    size(x,2)~=obj.NumReceiveAntennas||any(~isfinite(x(:)))
                error("WAVEFORM:InvalidObservationSamples","Received samples must be finite and match the physical RX branches.");
            end
            if obj.SampleClass~="" && obj.SampleClass~=string(class(x))
                error("WAVEFORM:ObservationPrecisionMismatch","RX precision cannot change between chunks.");
            end
            % All chunk validation precedes mutation of any observation.
            first=chunk.StartSample;
            stop=first+size(x,1);
            completed=struct('ID',{},'Observation',{},'CompletionSample',{},'ReceivedThroughSample',{});
            keep=true(numel(obj.Pending),1);
            for k=1:numel(obj.Pending)
                buffer=obj.Pending{k};
                lo=max(first,buffer.StartSample);
                hi=min(stop,buffer.EndSampleExclusive);
                if hi>lo
                    buffer.append(sixgr.phy.waveform.WaveformChunk( ...
                        x((lo-first+1):(hi-first),:),lo),obj.SampleRateHz);
                end
                if buffer.isComplete()
                    completed(end+1)=struct('ID',obj.PendingIDs(k), ...
                        'Observation',buffer,'CompletionSample',buffer.EndSampleExclusive, ...
                        'ReceivedThroughSample',stop); %#ok<AGROW>
                    keep(k)=false;
                end
            end
            obj.Pending=obj.Pending(keep);
            obj.PendingIDs=obj.PendingIDs(keep);
            obj.SampleClass=string(class(x));
            obj.NextSampleIndex=stop;
            if ~isempty(completed)
                [~,order]=sort([completed.CompletionSample]);
                completed=completed(order);
            end
        end
    end
end
