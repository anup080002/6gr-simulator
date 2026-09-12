classdef RuntimeTxIQStreamRecorder < handle
    %RUNTIMETXIQSTREAMRECORDER Disk-backed exact shared-clock Tx-IQ capture.
    %
    % The recorder accepts only the physical runtime's already composed,
    % power-scaled and TX-RF-processed antenna samples.  Each physical port
    % is appended as little-endian interleaved real/imaginary IEEE-754 data.
    % A PASS manifest is written only after the complete configured sample
    % horizon is proved contiguous for every registered transmitter.

    properties (SetAccess=private)
        RunFolder (1,1) string
        SampleRateHz (1,1) double
        CenterFrequencyHz (1,1) double
        ConfigurationEpoch (1,1) double
        NextSampleIndex (1,1) double = 0
        Started (1,1) logical = false
        Sealed (1,1) logical = false
    end

    properties (Access=private)
        Endpoints = struct('ID',{},'Direction',{},'NumPorts',{}, ...
            'Precision',{},'BytesPerReal',{},'PortPaths',{}, ...
            'MaxAbsComponent',{},'ActiveSampleCount',{})
        Segments = struct('SegmentIndex',{},'EndpointID',{}, ...
            'Direction',{},'StartSample',{},'EndSampleExclusive',{}, ...
            'SampleCountPerPort',{},'PortCount',{},'Precision',{}, ...
            'WaveformSHA256',{},'RFOutputWaveformSHA256',{}, ...
            'RFHashExactMatch',{},'ActiveSampleCount',{}, ...
            'MeanCompositePower',{},'PeakAbsComponent',{}, ...
            'Source',{},'ApproximationMode',{},'ProxyUsed',{}, ...
            'FallbackFlag',{},'PlaceholderFlag',{},'Status',{})
        BatchCount (1,1) double = 0
        FinalResult struct = struct()
    end

    methods
        function obj = RuntimeTxIQStreamRecorder(runFolder, cfg, sampleRateHz)
            arguments
                runFolder {mustBeTextScalar}
                cfg (1,1) struct
                sampleRateHz (1,1) double {mustBeFinite,mustBePositive}
            end
            runFolder = string(localAbsolutePath(runFolder));
            sixgr.util.ensureFolder(char(runFolder));
            obj.RunFolder = runFolder;
            obj.SampleRateHz = double(sampleRateHz);
            obj.CenterFrequencyHz = double(sixgr.util.structGet(cfg, ...
                'channel.fc_Hz',sixgr.util.structGet(cfg,'phy.fc_Hz',NaN)));
            obj.ConfigurationEpoch = double(sixgr.util.structGet( ...
                cfg,'rf.configurationEpoch',NaN));
            validateattributes(obj.CenterFrequencyHz,{'numeric'}, ...
                {'scalar','real','finite','positive'});
            validateattributes(obj.ConfigurationEpoch,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            sixgr.util.ensureFolder(fullfile(obj.RunFolder,'waveform','raw'));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder,'waveform','csv'));
        end

        function appendBatch(obj, nodes, waveforms, replays, first, stop)
            if obj.Sealed
                error('sixgr:truth:ContinuousTxIQAlreadySealed', ...
                    'A sealed continuous Tx-IQ capture cannot accept more samples.');
            end
            validateattributes(first,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            validateattributes(stop,{'numeric'}, ...
                {'scalar','real','finite','integer','>',first});
            if first ~= obj.NextSampleIndex
                error('sixgr:truth:ContinuousTxIQClockDiscontinuity', ...
                    'Continuous Tx-IQ expected sample %.0f but received %.0f.', ...
                    obj.NextSampleIndex,first);
            end
            if ~(isstruct(nodes) && all(isfield(nodes, ...
                    {'ID','Direction','NumPorts'})) && ...
                    iscell(waveforms) && numel(waveforms)==numel(nodes) && ...
                    isstruct(replays) && numel(replays)==numel(nodes) && ...
                    all(isfield(replays,'Replay')))
                error('sixgr:truth:ContinuousTxIQBatchSchema', ...
                    'Capture requires one waveform and TX-RF replay per physical transmitter.');
            end
            if isempty(nodes)
                error('sixgr:truth:ContinuousTxIQNoTransmitters', ...
                    'Continuous Tx-IQ capture cannot record an empty transmitter set.');
            end

            if ~obj.Started
                obj.initializeEndpoints(nodes,waveforms);
            end
            obj.validateEndpointIdentity(nodes,waveforms,stop-first);

            segmentHashes = strings(numel(nodes),1);
            replayHashes = strings(numel(nodes),1);
            for index=1:numel(nodes)
                samples=waveforms{index};
                segmentHashes(index)=string(sixgr.rf.waveformSHA256(samples));
                replayHashes(index)=string(sixgr.util.structGet( ...
                    replays(index).Replay,'RFOutputWaveformSHA256',''));
                if strlength(replayHashes(index))~=64 || ...
                        segmentHashes(index)~=replayHashes(index)
                    error('sixgr:truth:ContinuousTxIQRFHashMismatch', ...
                        ['Physical endpoint %s capture differs from the exact ' ...
                         'TX-RF output replay for samples [%d,%d).'], ...
                        string(nodes(index).ID),first,stop);
                end
            end

            % Validate every member before writing any member. A storage
            % error can still leave unsealed bytes, but never a PASS manifest.
            for index=1:numel(obj.Endpoints)
                endpoint=obj.Endpoints(index);
                samples=waveforms{index};
                for port=1:endpoint.NumPorts
                    localAppendComplexPort(endpoint.PortPaths(port), ...
                        samples(:,port),endpoint.Precision, ...
                        endpoint.BytesPerReal,first);
                end
            end

            obj.BatchCount=obj.BatchCount+1;
            for index=1:numel(obj.Endpoints)
                endpoint=obj.Endpoints(index);
                samples=waveforms{index};
                peak=max(abs([real(samples(:));imag(samples(:))]));
                active=sum(any(samples~=0,2));
                obj.Endpoints(index).MaxAbsComponent=max( ...
                    endpoint.MaxAbsComponent,double(peak));
                obj.Endpoints(index).ActiveSampleCount= ...
                    endpoint.ActiveSampleCount+double(active);
                row=localSegmentRow();
                row.SegmentIndex=obj.BatchCount;
                row.EndpointID=string(endpoint.ID);
                row.Direction=string(endpoint.Direction);
                row.StartSample=double(first);
                row.EndSampleExclusive=double(stop);
                row.SampleCountPerPort=double(stop-first);
                row.PortCount=double(endpoint.NumPorts);
                row.Precision=string(endpoint.Precision);
                row.WaveformSHA256=segmentHashes(index);
                row.RFOutputWaveformSHA256=replayHashes(index);
                row.RFHashExactMatch=true;
                row.ActiveSampleCount=double(active);
                row.MeanCompositePower=double(mean(abs(samples).^2,'all'));
                row.PeakAbsComponent=double(peak);
                row.Source='actual_shared_physical_transmitter_output';
                row.ApproximationMode='none';
                row.ProxyUsed=false;
                row.FallbackFlag=false;
                row.PlaceholderFlag=false;
                row.Status='PASS';
                obj.Segments(end+1)=row;
            end
            obj.NextSampleIndex=double(stop);
        end

        function result=finalize(obj, expectedEndSample, expectedSlotCount)
            if obj.Sealed
                result=obj.FinalResult;
                return;
            end
            validateattributes(expectedEndSample,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'});
            validateattributes(expectedSlotCount,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'});
            if ~obj.Started || obj.NextSampleIndex~=expectedEndSample
                error('sixgr:truth:ContinuousTxIQHorizonIncomplete', ...
                    'Capture ended at sample %.0f; configured horizon ends at %.0f.', ...
                    obj.NextSampleIndex,expectedEndSample);
            end

            rows=repmat(localManifestRow(),numel(obj.Endpoints),1);
            for index=1:numel(obj.Endpoints)
                endpoint=obj.Endpoints(index);
                segmentMask=string({obj.Segments.EndpointID})==string(endpoint.ID);
                segments=obj.Segments(segmentMask);
                starts=double([segments.StartSample]);
                stops=double([segments.EndSampleExclusive]);
                if isempty(segments) || numel(segments)~=expectedSlotCount || ...
                        starts(1)~=0 || stops(end)~=expectedEndSample || ...
                        any(starts(2:end)~=stops(1:end-1))
                    error('sixgr:truth:ContinuousTxIQCoverageGap', ...
                        ['Endpoint %s has %d segments for %d scheduler slots or ' ...
                         'does not cover [0,%d) contiguously.'], ...
                        string(endpoint.ID),numel(segments),expectedSlotCount, ...
                        expectedEndSample);
                end
                hashes=strings(endpoint.NumPorts,1);
                totalBytes=0;
                expectedBytes=expectedEndSample*2*endpoint.BytesPerReal;
                for port=1:endpoint.NumPorts
                    info=dir(endpoint.PortPaths(port));
                    if isempty(info) || double(info.bytes)~=expectedBytes
                        error('sixgr:truth:ContinuousTxIQFileExtentMismatch', ...
                            ['Endpoint %s port %d contains %g bytes; the complete ' ...
                             'sample horizon requires %g.'],string(endpoint.ID), ...
                            port,localFileBytes(info),expectedBytes);
                    end
                    hashes(port)=localFileSHA256(endpoint.PortPaths(port));
                    totalBytes=totalBytes+double(info.bytes);
                end
                row=localManifestRow();
                row.EndpointID=string(endpoint.ID);
                row.Direction=string(endpoint.Direction);
                row.CapturePoint= ...
                    'physical_antenna_output_after_composition_power_scaling_and_tx_rf_before_channel';
                row.WaveformAuthority='exact_shared_physical_runtime_stream';
                row.SampleRateHz=obj.SampleRateHz;
                row.CenterFrequencyHz=obj.CenterFrequencyHz;
                row.ConfigurationEpoch=obj.ConfigurationEpoch;
                row.CaptureStartSample=0;
                row.CaptureEndSampleExclusive=expectedEndSample;
                row.SampleCountPerPort=expectedEndSample;
                row.PortCount=endpoint.NumPorts;
                row.SchedulerSlotCount=expectedSlotCount;
                row.SegmentCount=numel(segments);
                row.Precision=string(endpoint.Precision);
                row.BinaryLayout='per_port_interleaved_I0_Q0_I1_Q1_little_endian';
                relativePortPaths=strings(endpoint.NumPorts,1);
                for port=1:endpoint.NumPorts
                    relativePortPaths(port)=localRelativePath( ...
                        obj.RunFolder,endpoint.PortPaths(port));
                end
                row.PortFiles=strjoin(relativePortPaths,'|');
                row.PortFileSHA256=strjoin(hashes,'|');
                row.TotalFileBytes=totalBytes;
                row.PeakAbsComponent=endpoint.MaxAbsComponent;
                row.ActiveSampleCount=endpoint.ActiveSampleCount;
                row.ContinuousCoverage=true;
                row.AllSchedulerSamplesIncluded=true;
                row.CompositeTransmitterWaveform=true;
                row.IncludesIntentionalSilence=true;
                row.KeysightNormalizationRequired=true;
                row.Source='actual_shared_physical_transmitter_output';
                row.ApproximationMode='none';
                row.ProxyUsed=false;
                row.FallbackFlag=false;
                row.PlaceholderFlag=false;
                row.CaptureStatus='PASS';
                rows(index)=row;
            end

            segmentT=struct2table(obj.Segments,'AsArray',true);
            manifestT=struct2table(rows,'AsArray',true);
            csvDir=fullfile(obj.RunFolder,'waveform','csv');
            segmentPath=fullfile(csvDir,'continuous_tx_iq_segments.csv');
            manifestPath=fullfile(csvDir,'continuous_tx_iq_capture_manifest.csv');
            sixgr.util.csvWriteTable(segmentPath,segmentT,'PreserveSchema',true);
            sixgr.util.csvWriteTable(manifestPath,manifestT,'PreserveSchema',true);
            obj.Sealed=true;
            obj.FinalResult=struct('Ok',true,'ManifestPath',string(manifestPath), ...
                'SegmentPath',string(segmentPath),'ManifestTable',manifestT, ...
                'SegmentTable',segmentT,'SampleCount',expectedEndSample, ...
                'EndpointCount',numel(obj.Endpoints));
            result=obj.FinalResult;
        end
    end

    methods (Access=private)
        function initializeEndpoints(obj,nodes,waveforms)
            ids=string({nodes.ID});
            if numel(unique(ids))~=numel(ids)
                error('sixgr:truth:ContinuousTxIQDuplicateEndpoint', ...
                    'Every physical transmitter capture needs a unique endpoint ID.');
            end
            rawDir=fullfile(obj.RunFolder,'waveform','raw');
            for index=1:numel(nodes)
                id=string(nodes(index).ID);
                direction=upper(string(nodes(index).Direction));
                numPorts=double(nodes(index).NumPorts);
                samples=waveforms{index};
                if ~isscalar(id) || isempty(regexp(id,'^[A-Za-z0-9_]+$','once')) || ...
                        ~any(direction==["DL","UL"]) || ...
                        ~(isscalar(numPorts) && isfinite(numPorts) && ...
                          numPorts>=1 && numPorts==fix(numPorts))
                    error('sixgr:truth:ContinuousTxIQEndpointIdentity', ...
                        'Physical transmitter identity, direction or port count is invalid.');
                end
                precision=string(class(samples));
                if precision=='double'
                    bytesPerReal=8;
                    suffix='cf64le';
                elseif precision=='single'
                    bytesPerReal=4;
                    suffix='cf32le';
                else
                    error('sixgr:truth:ContinuousTxIQPrecision', ...
                        'Continuous Tx-IQ supports exact single or double samples.');
                end
                portPaths=strings(numPorts,1);
                for port=1:numPorts
                    portPaths(port)=string(fullfile(rawDir,sprintf( ...
                        'continuous_tx_iq_%s_port%d_%s.bin', ...
                        lower(id),port,suffix)));
                    if isfile(portPaths(port))
                        error('sixgr:truth:ContinuousTxIQRefusesOverwrite', ...
                            'Continuous Tx-IQ refuses to overwrite %s.',portPaths(port));
                    end
                end
                obj.Endpoints(end+1)=struct('ID',id,'Direction',direction, ...
                    'NumPorts',numPorts,'Precision',precision, ...
                    'BytesPerReal',bytesPerReal,'PortPaths',portPaths, ...
                    'MaxAbsComponent',0,'ActiveSampleCount',0);
            end
            obj.Started=true;
        end

        function validateEndpointIdentity(obj,nodes,waveforms,sampleCount)
            if numel(nodes)~=numel(obj.Endpoints)
                error('sixgr:truth:ContinuousTxIQEndpointSetChanged', ...
                    'Physical transmitter membership changed after capture began.');
            end
            for index=1:numel(obj.Endpoints)
                endpoint=obj.Endpoints(index);
                samples=waveforms{index};
                if string(nodes(index).ID)~=string(endpoint.ID) || ...
                        upper(string(nodes(index).Direction))~=string(endpoint.Direction) || ...
                        double(nodes(index).NumPorts)~=endpoint.NumPorts || ...
                        ~isa(samples,char(endpoint.Precision)) || ...
                        ~isequal(size(samples),[sampleCount endpoint.NumPorts]) || ...
                        any(~isfinite(samples),'all')
                    error('sixgr:truth:ContinuousTxIQEndpointSetChanged', ...
                        'Physical transmitter layout, precision or sample extent changed.');
                end
            end
        end
    end
end

function row=localSegmentRow()
row=struct('SegmentIndex',NaN,'EndpointID',"",'Direction',"", ...
    'StartSample',NaN,'EndSampleExclusive',NaN,'SampleCountPerPort',NaN, ...
    'PortCount',NaN,'Precision',"",'WaveformSHA256',"", ...
    'RFOutputWaveformSHA256',"",'RFHashExactMatch',false, ...
    'ActiveSampleCount',NaN,'MeanCompositePower',NaN, ...
    'PeakAbsComponent',NaN,'Source',"",'ApproximationMode',"", ...
    'ProxyUsed',false,'FallbackFlag',false,'PlaceholderFlag',false, ...
    'Status',"");
end

function row=localManifestRow()
row=struct('EndpointID',"",'Direction',"",'CapturePoint',"", ...
    'WaveformAuthority',"",'SampleRateHz',NaN,'CenterFrequencyHz',NaN, ...
    'ConfigurationEpoch',NaN,'CaptureStartSample',NaN, ...
    'CaptureEndSampleExclusive',NaN,'SampleCountPerPort',NaN, ...
    'PortCount',NaN,'SchedulerSlotCount',NaN,'SegmentCount',NaN, ...
    'Precision',"",'BinaryLayout',"",'PortFiles',"", ...
    'PortFileSHA256',"",'TotalFileBytes',NaN,'PeakAbsComponent',NaN, ...
    'ActiveSampleCount',NaN,'ContinuousCoverage',false, ...
    'AllSchedulerSamplesIncluded',false,'CompositeTransmitterWaveform',false, ...
    'IncludesIntentionalSilence',false,'KeysightNormalizationRequired',true, ...
    'Source',"",'ApproximationMode',"",'ProxyUsed',false, ...
    'FallbackFlag',false,'PlaceholderFlag',false,'CaptureStatus',"");
end

function localAppendComplexPort(pathValue,samples,precision,bytesPerReal,first)
pathValue=char(string(pathValue));
expectedBefore=double(first)*2*double(bytesPerReal);
if isfile(pathValue)
    info=dir(pathValue);
    actualBefore=double(info.bytes);
else
    actualBefore=0;
end
if actualBefore~=expectedBefore
    error('sixgr:truth:ContinuousTxIQFileClockMismatch', ...
        'Raw Tx-IQ file %s has %g bytes; expected %g before append.', ...
        pathValue,actualBefore,expectedBefore);
end
mode='ab';
if first==0, mode='wb'; end
fid=fopen(pathValue,mode,'ieee-le');
if fid<0
    error('sixgr:truth:ContinuousTxIQFileOpenFailed', ...
        'Cannot open continuous Tx-IQ file %s.',pathValue);
end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
values=reshape([real(samples(:)).';imag(samples(:)).'],[],1);
count=fwrite(fid,values,char(precision));
clear cleanup;
if count~=numel(values)
    error('sixgr:truth:ContinuousTxIQShortWrite', ...
        'Continuous Tx-IQ wrote %d of %d real components.',count,numel(values));
end
info=dir(pathValue);
expectedAfter=expectedBefore+numel(values)*double(bytesPerReal);
if isempty(info) || double(info.bytes)~=expectedAfter
    error('sixgr:truth:ContinuousTxIQFileExtentMismatch', ...
        'Continuous Tx-IQ file extent differs from the committed sample clock.');
end
end

function pathOut=localAbsolutePath(pathValue)
pathOut=char(string(pathValue));
javaFile=java.io.File(pathOut);
pathOut=char(javaFile.getCanonicalPath());
end

function relative=localRelativePath(root,pathValue)
root=replace(string(localAbsolutePath(root)),"\","/");
pathValue=replace(string(localAbsolutePath(pathValue)),"\","/");
if ~startsWith(lower(pathValue),lower(root+"/"))
    error('sixgr:truth:ContinuousTxIQPathEscape', ...
        'Capture artifact is outside its run folder.');
end
relative=extractAfter(pathValue,strlength(root)+1);
end

function hash=localFileSHA256(pathValue)
hash=lower(string(sixgr.util.sha256File(char(string(pathValue)))));
end

function bytes=localFileBytes(info)
if isempty(info), bytes=NaN; else, bytes=double(info(1).bytes); end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('sixgr:truth:ContinuousTxIQPathType', ...
        'Continuous Tx-IQ run folder must be a text scalar.');
end
end
