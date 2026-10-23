classdef WaveformObservationBuffer < handle
    %WAVEFORMOBSERVATIONBUFFER Contiguous received samples, never padded gaps.
    % Read access is gated by received sample coverage, not planned duration.
    properties (SetAccess=private)
        StartSample (1,1) double
        EndSampleExclusive (1,1) double
        ReceivedThroughSample (1,1) double
        SampleRateHz (1,1) double
        NumReceiveAntennas (1,1) double
    end
    properties (Access=private)
        Parts = cell(0,1)
        SampleClass (1,1) string = ""
        CompleteSampleHash (1,1) string = ""
        CompleteSamples = []
        CompletedArchive = struct()
    end
    methods
        function obj=WaveformObservationBuffer(startSample,endSampleExclusive,sampleRateHz,numRx)
            validateattributes(startSample,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            validateattributes(endSampleExclusive,{'numeric'}, ...
                {'scalar','real','finite','integer','>',startSample});
            validateattributes(sampleRateHz,{'numeric'}, ...
                {'scalar','real','finite','positive'});
            validateattributes(numRx,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'});
            obj.StartSample=double(startSample);
            obj.EndSampleExclusive=double(endSampleExclusive);
            obj.ReceivedThroughSample=double(startSample);
            obj.SampleRateHz=double(sampleRateHz);
            obj.NumReceiveAntennas=double(numRx);
        end

        function append(obj,chunk,sampleRateHz)
            if ~isa(chunk,'sixgr.phy.waveform.WaveformChunk')||~isscalar(chunk)
                error("WAVEFORM:InvalidObservationChunk","Append one received WaveformChunk.");
            end
            if ~isnumeric(sampleRateHz)||~isscalar(sampleRateHz)|| ...
                    ~isreal(sampleRateHz)||~isfinite(sampleRateHz)|| ...
                    sampleRateHz~=obj.SampleRateHz
                error("WAVEFORM:ObservationSampleRateMismatch","RX chunks must share the observation sample clock.");
            end
            if chunk.StartSample~=obj.ReceivedThroughSample
                error("WAVEFORM:ObservationDiscontinuity", ...
                    "Expected received sample %.0f; got %.0f. Gaps and overlapping replay are forbidden.", ...
                    obj.ReceivedThroughSample,chunk.StartSample);
            end
            x=chunk.Samples;
            if ~(isa(x,'single')||isa(x,'double'))||~ismatrix(x)||isempty(x)|| ...
                    size(x,2)~=obj.NumReceiveAntennas||any(~isfinite(x(:)))
                error("WAVEFORM:InvalidObservationSamples", ...
                    "RX samples must be finite and match the observation's receive antennas.");
            end
            stop=chunk.StartSample+size(x,1);
            if stop>obj.EndSampleExclusive
                error("WAVEFORM:ObservationOverrun","Split received chunks at the observation boundary; do not truncate them implicitly.");
            end
            if obj.SampleClass~="" && obj.SampleClass~=string(class(x))
                error("WAVEFORM:ObservationPrecisionMismatch","RX sample precision must remain unchanged.");
            end
            obj.Parts{end+1,1}=chunk;
            obj.SampleClass=string(class(x));
            obj.ReceivedThroughSample=stop;
        end

        function tf=isComplete(obj)
            tf=obj.ReceivedThroughSample==obj.EndSampleExclusive;
        end

        function samples=readComplete(obj)
            if ~obj.isComplete()
                error("WAVEFORM:IncompleteObservation", ...
                    "Only samples through %.0f have arrived; acquisition needs samples through %.0f.", ...
                    obj.ReceivedThroughSample,obj.EndSampleExclusive);
            end
            if ~isempty(fieldnames(obj.CompletedArchive))
                samples=sixgr.phy.waveform.CompletedSampleArchive.read(obj.CompletedArchive);
                return;
            elseif ~isempty(obj.CompleteSamples)
                samples=obj.CompleteSamples;
                return;
            elseif numel(obj.Parts)==1
                samples=obj.Parts{1}.Samples;
                return;
            end
            scope=sixgr.runtime.ExecutionStageProfiler.scope("buffers","compact_completed_observation"); %#ok<NASGU>
            arrays=cellfun(@(part) part.Samples,obj.Parts,'UniformOutput',false);
            samples=vertcat(arrays{:});
            % Replace the chunk owners, rather than adding a second cache.
            % Subsequent reads share this exact immutable MATLAB value until
            % a caller modifies its own copy. No precision conversion.
            obj.CompleteSamples=samples;
            obj.Parts=cell(0,1);
        end

        function digest=sampleHash(obj)
            assert(obj.isComplete(),'WAVEFORM:IncompleteObservation', ...
                'Incomplete captures never get hashes.');
            if ~isempty(fieldnames(obj.CompletedArchive)) && strlength(obj.CompleteSampleHash)>0
                verified=sixgr.phy.waveform.CompletedSampleArchive.verifyFile(obj.CompletedArchive);
                assert(verified==obj.CompleteSampleHash,'WAVEFORM:ArchiveIdentity', ...
                    'Cached sample identity must match its validated archive.');
                digest=obj.CompleteSampleHash;
                return;
            end
            if strlength(obj.CompleteSampleHash)==0
                samples=obj.readComplete();
                obj.CompleteSampleHash=sixgr.phy.waveform.WaveformHash.runtimeArray(samples);
            end
            digest=obj.CompleteSampleHash;
        end

        function receipt=archiveCompleted(obj,root)
            % Keep incomplete observations in the live owner. The archive
            % is independently read back before releasing complete arrays.
            if ~isempty(fieldnames(obj.CompletedArchive))
                receipt=obj.CompletedArchive;
                return;
            end
            samples=obj.readComplete();
            receipt=sixgr.phy.waveform.CompletedSampleArchive.write(root,samples);
            obj.CompletedArchive=receipt;
            obj.CompleteSampleHash=receipt.Manifest.SampleSHA256;
            obj.Parts=cell(0,1);
            obj.CompleteSamples=[];
        end

        function info=storageInfo(obj)
            info=struct('RetainedArrays',numel(obj.Parts)+double(~isempty(obj.CompleteSamples)), ...
                'ReceivedSamples',obj.ReceivedThroughSample-obj.StartSample, ...
                'SampleClass',obj.SampleClass,'Complete',obj.isComplete(), ...
                'HashCached',strlength(obj.CompleteSampleHash)>0, ...
                'Archived',~isempty(fieldnames(obj.CompletedArchive)));
        end
    end
end
