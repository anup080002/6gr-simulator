function result=exportContinuousKeysightPlaybackPackage(sourceRunFolder,outputFolder)
%EXPORTCONTINUOUSKEYSIGHTPLAYBACKPACKAGE Package sealed shared-clock Tx IQ.
%
% The source float binaries remain untouched. Each physical antenna port is
% verified against the sealed continuous-capture manifest, normalized with
% one common scale per physical transmitter, and exported as headerless I/Q
% CSV, little-endian signed-int16 WIQ and an 89600 VSA MATLAB source file.

arguments
    sourceRunFolder {mustBeTextScalar}
    outputFolder {mustBeTextScalar}
end

sourceRunFolder=localCanonicalFolder(sourceRunFolder);
outputFolder=localAbsolutePath(outputFolder);
sourceKey=lower(replace(string(sourceRunFolder),"\","/"));
outputKey=lower(replace(string(outputFolder),"\","/"));
if outputKey==sourceKey || startsWith(outputKey,sourceKey+"/")
    error('sixgr:truth:ContinuousKeysightPackageInsideSource', ...
        'Continuous Keysight packaging requires a separate output tree.');
end

sourceManifestPath=fullfile(sourceRunFolder,'waveform','csv', ...
    'continuous_tx_iq_capture_manifest.csv');
sourceSegmentPath=fullfile(sourceRunFolder,'waveform','csv', ...
    'continuous_tx_iq_segments.csv');
if ~isfile(sourceManifestPath) || ~isfile(sourceSegmentPath)
    error('sixgr:truth:ContinuousKeysightSourceMissing', ...
        'The source run has no sealed continuous Tx-IQ manifest and segment table.');
end
source=sixgr.util.csvReadTable(sourceManifestPath,'TextType','string');
segments=sixgr.util.csvReadTable(sourceSegmentPath,'TextType','string');
localValidateSourceTables(source,segments);

csvDir=fullfile(outputFolder,'waveform','csv');
matDir=fullfile(outputFolder,'waveform','mat');
sixgr.util.ensureFolder(csvDir);
sixgr.util.ensureFolder(matDir);
manifestPath=fullfile(csvDir,'continuous_keysight_playback_manifest.csv');
if isfile(manifestPath)
    error('sixgr:truth:ContinuousKeysightRefusesOverwrite', ...
        'Continuous Keysight package manifest already exists: %s',manifestPath);
end

rowCount=sum(double(source.PortCount));
rows=repmat(localOutputRow(),rowCount,1);
rowIndex=0;
sourceManifestHash=localFileSHA256(sourceManifestPath);
sourceSegmentHash=localFileSHA256(sourceSegmentPath);
for endpointIndex=1:height(source)
    endpointID=string(source.EndpointID(endpointIndex));
    direction=upper(string(source.Direction(endpointIndex)));
    sampleCount=double(source.SampleCountPerPort(endpointIndex));
    portCount=double(source.PortCount(endpointIndex));
    sampleRateHz=double(source.SampleRateHz(endpointIndex));
    centerFrequencyHz=double(source.CenterFrequencyHz(endpointIndex));
    precision=lower(string(source.Precision(endpointIndex)));
    if ~isscalar(endpointID) || isempty(regexp(endpointID, ...
            '^[A-Za-z0-9_]+$','once')) || ~ismember(direction,["DL","UL"])
        error('sixgr:truth:ContinuousKeysightEndpointIdentity', ...
            'Source endpoint identity or direction is invalid.');
    end
    if ~(isfinite(sampleCount) && sampleCount>=1024 && ...
            sampleCount==fix(sampleCount) && mod(sampleCount,16)==0 && ...
            isfinite(portCount) && portCount>=1 && portCount==fix(portCount) && ...
            isfinite(sampleRateHz) && sampleRateHz>0 && ...
            isfinite(centerFrequencyHz) && centerFrequencyHz>0)
        error('sixgr:truth:ContinuousKeysightPlaybackDimensions', ...
            ['Endpoint %s violates the positive clock/port contract or the ' ...
             'M9384B minimum-1024/multiple-of-16 sample extent.'],endpointID);
    end
    sourceFiles=split(string(source.PortFiles(endpointIndex)),'|');
    sourceHashes=lower(split(string(source.PortFileSHA256(endpointIndex)),'|'));
    if numel(sourceFiles)~=portCount || numel(sourceHashes)~=portCount
        error('sixgr:truth:ContinuousKeysightPortManifestMismatch', ...
            'Endpoint %s port paths/hashes do not match PortCount.',endpointID);
    end

    portWaveforms=cell(portCount,1);
    observedFullScale=0;
    for port=1:portCount
        sourcePath=localResolveChild(sourceRunFolder,sourceFiles(port));
        if localFileSHA256(sourcePath)~=sourceHashes(port)
            error('sixgr:truth:ContinuousKeysightSourceHashMismatch', ...
                'Endpoint %s port %d differs from its sealed source hash.', ...
                endpointID,port);
        end
        portWaveforms{port}=localReadComplexBinary( ...
            sourcePath,precision,sampleCount);
        observedFullScale=max(observedFullScale,max(abs([ ...
            real(portWaveforms{port});imag(portWaveforms{port})])));
    end
    declaredPeak=double(source.PeakAbsComponent(endpointIndex));
    tolerance=8*eps(max(1,max(abs([declaredPeak observedFullScale]))));
    if abs(declaredPeak-observedFullScale)>tolerance
        error('sixgr:truth:ContinuousKeysightPeakMismatch', ...
            'Endpoint %s source peak differs from its sealed manifest.',endpointID);
    end
    normalizationScale=observedFullScale;
    normalizationPolicy="common_endpoint_peak_preserves_port_amplitude_and_phase";
    if normalizationScale==0
        normalizationScale=1;
        normalizationPolicy="identity_scale_for_exact_intentional_silence";
    end

    for port=1:portCount
        rowIndex=rowIndex+1;
        waveform=portWaveforms{port};
        normalized=double(waveform)./normalizationScale;
        token=sprintf('%s_port%d',lower(char(endpointID)),port);
        csvPath=fullfile(csvDir,"continuous_tx_iq_"+token+"_keysight.csv");
        wiqPath=fullfile(csvDir,"continuous_tx_iq_"+token+"_keysight_le16.wiq");
        vsaPath=fullfile(matDir,"continuous_tx_iq_"+token+"_89600vsa.mat");
        localRefuseArtifacts([string(csvPath);string(wiqPath);string(vsaPath)]);
        localWriteIQCSV(csvPath,normalized);

        scaledI=round(real(normalized).*32767);
        scaledQ=round(imag(normalized).*32767);
        clipped=sum(scaledI < -32767 | scaledI > 32767 | ...
            scaledQ < -32767 | scaledQ > 32767);
        quantizedI=int16(max(-32767,min(32767,scaledI)));
        quantizedQ=int16(max(-32767,min(32767,scaledQ)));
        interleaved=zeros(2*sampleCount,1,'int16');
        interleaved(1:2:end)=quantizedI;
        interleaved(2:2:end)=quantizedQ;
        localAtomicInt16Write(wiqPath,interleaved);
        observedCodes=localReadInt16(wiqPath,2*sampleCount);
        if ~isequal(observedCodes,interleaved)
            error('sixgr:truth:ContinuousKeysightWIQRoundtripMismatch', ...
                'Endpoint %s port %d WIQ readback differs from written codes.', ...
                endpointID,port);
        end
        reconstructed=complex(double(quantizedI),double(quantizedQ))./32767;

        payload=struct('Y',single(normalized),'XDelta',double(1/sampleRateHz), ...
            'InputCenter',centerFrequencyHz,'InputZoom',1,'XDomain',2);
        sixgr.util.matSave(vsaPath,payload,'UseArtifactStore',false);
        localValidateVSAMAT(vsaPath,payload,sampleCount);

        row=localOutputRow();
        row.EndpointID=endpointID;
        row.Direction=direction;
        row.PortIndex=port;
        row.SynchronizedPortCount=portCount;
        row.CaptureStartSample=double(source.CaptureStartSample(endpointIndex));
        row.CaptureEndSampleExclusive=double(source.CaptureEndSampleExclusive(endpointIndex));
        row.SampleCount=sampleCount;
        row.SampleRateHz=sampleRateHz;
        row.CenterFrequencyHz=centerFrequencyHz;
        row.SourceCapturePoint=string(source.CapturePoint(endpointIndex));
        row.SourceWaveformAuthority=string(source.WaveformAuthority(endpointIndex));
        row.SourcePrecision=precision;
        row.SourcePortFile=sourceFiles(port);
        row.SourcePortFileSHA256=sourceHashes(port);
        row.SourceCaptureManifest=localRelativePath(sourceRunFolder,sourceManifestPath);
        row.SourceCaptureManifestSHA256=sourceManifestHash;
        row.SourceSegmentTable=localRelativePath(sourceRunFolder,sourceSegmentPath);
        row.SourceSegmentTableSHA256=sourceSegmentHash;
        row.CommonEndpointNormalizationFullScale=normalizationScale;
        row.NormalizationPolicy=normalizationPolicy;
        row.NormalizedPeak=max(abs([real(normalized);imag(normalized)]));
        row.NormalizedRMS=sqrt(mean(abs(normalized).^2));
        row.KeysightCSV=localRelativePath(outputFolder,csvPath);
        row.KeysightCSV_SHA256=localFileSHA256(csvPath);
        row.KeysightInt16=localRelativePath(outputFolder,wiqPath);
        row.KeysightInt16SHA256=localFileSHA256(wiqPath);
        row.KeysightInt16ByteOrder='little_endian';
        row.KeysightInt16QuantizationScale=32767;
        row.KeysightInt16PeakCode=max(abs(double(interleaved)));
        row.KeysightInt16ClippedComponentCount=double(clipped);
        row.KeysightInt16MaxComplexError=max(abs(reconstructed-normalized));
        row.KeysightVSAMAT=localRelativePath(outputFolder,vsaPath);
        row.KeysightVSAMATSHA256=localFileSHA256(vsaPath);
        row.KeysightVSAMATSchema= ...
            'Y=complex_single;XDelta=seconds;InputCenter=Hz;InputZoom=1;XDomain=2';
        row.MIMOPlaybackAlignment= ...
            'sample_zero_common_clock_equal_length_one_file_per_physical_port';
        row.PlaybackRepeatPolicy='operator_selected_no_implicit_repeat';
        row.PlaybackInstrumentTargets='M9384B|M9383B|89600_VSA';
        row.CompositeTransmitterWaveform= ...
            localLogical(source.CompositeTransmitterWaveform(endpointIndex));
        row.IncludesIntentionalSilence= ...
            localLogical(source.IncludesIntentionalSilence(endpointIndex));
        row.SourceApproximationMode=string(source.ApproximationMode(endpointIndex));
        row.ProxyUsed=false;
        row.FallbackFlag=false;
        row.PlaceholderFlag=false;
        row.PhysicalInstrumentValidationStatus= ...
            'not_executed_requires_physical_instrument';
        row.Status='PASS';
        rows(rowIndex)=row;
    end
end

manifest=struct2table(rows,'AsArray',true);
sixgr.util.csvWriteTable(manifestPath,manifest,'PreserveSchema',true);
result=struct('Ok',true,'SourceRunFolder',string(sourceRunFolder), ...
    'OutputFolder',string(outputFolder),'ManifestPath',string(manifestPath), ...
    'ManifestTable',manifest,'EndpointCount',height(source), ...
    'PortArtifactCount',height(manifest));
end

function localValidateSourceTables(source,segments)
requiredManifest=["EndpointID","Direction","CapturePoint", ...
    "WaveformAuthority","SampleRateHz","CenterFrequencyHz", ...
    "CaptureStartSample","CaptureEndSampleExclusive","SampleCountPerPort", ...
    "PortCount","SchedulerSlotCount","SegmentCount","Precision", ...
    "BinaryLayout","PortFiles","PortFileSHA256","PeakAbsComponent", ...
    "ContinuousCoverage","AllSchedulerSamplesIncluded", ...
    "CompositeTransmitterWaveform","IncludesIntentionalSilence", ...
    "ApproximationMode","ProxyUsed","FallbackFlag","PlaceholderFlag", ...
    "CaptureStatus"];
requiredSegments=["EndpointID","StartSample","EndSampleExclusive", ...
    "RFHashExactMatch","ApproximationMode","ProxyUsed","FallbackFlag", ...
    "PlaceholderFlag","Status"];
localRequireColumns(source,requiredManifest,'capture manifest');
localRequireColumns(segments,requiredSegments,'segment table');
if isempty(source) || isempty(segments) || ...
        any(~strcmpi(string(source.CaptureStatus),'PASS')) || ...
        any(~localLogical(source.ContinuousCoverage)) || ...
        any(~localLogical(source.AllSchedulerSamplesIncluded)) || ...
        any(lower(string(source.ApproximationMode))~="none") || ...
        any(localLogical(source.ProxyUsed)|localLogical(source.FallbackFlag)| ...
            localLogical(source.PlaceholderFlag)) || ...
        any(~strcmpi(string(segments.Status),'PASS')) || ...
        any(~localLogical(segments.RFHashExactMatch)) || ...
        any(lower(string(segments.ApproximationMode))~="none") || ...
        any(localLogical(segments.ProxyUsed)|localLogical(segments.FallbackFlag)| ...
            localLogical(segments.PlaceholderFlag))
    error('sixgr:truth:ContinuousKeysightSourceNotTruth', ...
        'Keysight packaging requires complete non-proxy PASS source evidence.');
end
if numel(unique(string(source.EndpointID)))~=height(source)
    error('sixgr:truth:ContinuousKeysightDuplicateEndpoint', ...
        'The continuous capture manifest contains duplicate endpoint IDs.');
end
commonClock=[double(source.CaptureStartSample), ...
    double(source.CaptureEndSampleExclusive),double(source.SampleCountPerPort), ...
    double(source.SampleRateHz),double(source.CenterFrequencyHz), ...
    double(source.SchedulerSlotCount)];
if any(~isfinite(commonClock),'all') || any(commonClock(:,1)~=0) || ...
        any(commonClock~=commonClock(1,:),'all')
    error('sixgr:truth:ContinuousKeysightCommonClock', ...
        ['Every physical transmitter must begin at sample zero and retain ' ...
         'the same horizon, sample rate, center frequency and slot count.']);
end
for index=1:height(source)
    endpointID=string(source.EndpointID(index));
    mask=string(segments.EndpointID)==endpointID;
    selected=segments(mask,:);
    starts=double(selected.StartSample);
    stops=double(selected.EndSampleExclusive);
    expectedSegments=double(source.SchedulerSlotCount(index));
    if height(selected)~=expectedSegments || ...
            height(selected)~=double(source.SegmentCount(index)) || ...
            isempty(starts) || starts(1)~=double(source.CaptureStartSample(index)) || ...
            stops(end)~=double(source.CaptureEndSampleExclusive(index)) || ...
            any(starts(2:end)~=stops(1:end-1)) || ...
            double(source.SampleCountPerPort(index))~=stops(end)-starts(1) || ...
            string(source.BinaryLayout(index))~= ...
                "per_port_interleaved_I0_Q0_I1_Q1_little_endian"
        error('sixgr:truth:ContinuousKeysightSourceCoverage', ...
            'Endpoint %s is not a contiguous one-segment-per-slot capture.',endpointID);
    end
end
end

function row=localOutputRow()
row=struct('EndpointID',"",'Direction',"",'PortIndex',NaN, ...
    'SynchronizedPortCount',NaN,'CaptureStartSample',NaN, ...
    'CaptureEndSampleExclusive',NaN,'SampleCount',NaN, ...
    'SampleRateHz',NaN,'CenterFrequencyHz',NaN,'SourceCapturePoint',"", ...
    'SourceWaveformAuthority',"",'SourcePrecision',"", ...
    'SourcePortFile',"",'SourcePortFileSHA256',"", ...
    'SourceCaptureManifest',"",'SourceCaptureManifestSHA256',"", ...
    'SourceSegmentTable',"",'SourceSegmentTableSHA256',"", ...
    'CommonEndpointNormalizationFullScale',NaN,'NormalizationPolicy',"", ...
    'NormalizedPeak',NaN,'NormalizedRMS',NaN,'KeysightCSV',"", ...
    'KeysightCSV_SHA256',"",'KeysightInt16',"", ...
    'KeysightInt16SHA256',"",'KeysightInt16ByteOrder',"", ...
    'KeysightInt16QuantizationScale',NaN,'KeysightInt16PeakCode',NaN, ...
    'KeysightInt16ClippedComponentCount',NaN, ...
    'KeysightInt16MaxComplexError',NaN,'KeysightVSAMAT',"", ...
    'KeysightVSAMATSHA256',"",'KeysightVSAMATSchema',"", ...
    'MIMOPlaybackAlignment',"",'PlaybackRepeatPolicy',"", ...
    'PlaybackInstrumentTargets',"",'CompositeTransmitterWaveform',false, ...
    'IncludesIntentionalSilence',false,'SourceApproximationMode',"", ...
    'ProxyUsed',false,'FallbackFlag',false,'PlaceholderFlag',false, ...
    'PhysicalInstrumentValidationStatus',"",'Status',"");
end

function localRequireColumns(T,required,label)
missing=setdiff(required,string(T.Properties.VariableNames));
if ~isempty(missing)
    error('sixgr:truth:ContinuousKeysightSourceSchema', ...
        'Continuous Tx-IQ %s is missing: %s.',label,strjoin(missing,', '));
end
end

function waveform=localReadComplexBinary(pathValue,precision,sampleCount)
if ~ismember(precision,["double","single"])
    error('sixgr:truth:ContinuousKeysightSourcePrecision', ...
        'Unsupported continuous source precision %s.',precision);
end
bytesPerReal=8;
if precision=="single", bytesPerReal=4; end
info=dir(pathValue);
if isempty(info) || double(info.bytes)~=sampleCount*2*bytesPerReal
    error('sixgr:truth:ContinuousKeysightSourceExtent', ...
        'Continuous source binary has the wrong byte extent.');
end
fid=fopen(pathValue,'rb','ieee-le');
if fid<0
    error('sixgr:truth:ContinuousKeysightSourceOpen', ...
        'Cannot open continuous source binary %s.',pathValue);
end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
values=fread(fid,[2 sampleCount],char(precision)+"=>double");
if numel(values)~=2*sampleCount
    error('sixgr:truth:ContinuousKeysightSourceShortRead', ...
        'Continuous source binary ended before its declared sample count.');
end
waveform=complex(values(1,:),values(2,:)).';
end

function localWriteIQCSV(pathValue,waveform)
tmpPath=char(string(tempname())+'.csv');
cleanup=onCleanup(@()localDeleteIfExists(tmpPath)); %#ok<NASGU>
writematrix([real(waveform),imag(waveform)],tmpPath,'Delimiter',',');
localPublish(tmpPath,pathValue);
end

function localAtomicInt16Write(pathValue,values)
tmpPath=char(string(tempname())+'.wiq');
cleanup=onCleanup(@()localDeleteIfExists(tmpPath)); %#ok<NASGU>
fid=fopen(tmpPath,'wb','ieee-le');
if fid<0
    error('sixgr:truth:ContinuousKeysightWIQOpen', ...
        'Cannot open temporary WIQ file.');
end
closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
count=fwrite(fid,values,'int16');
clear closeFile;
if count~=numel(values)
    error('sixgr:truth:ContinuousKeysightWIQShortWrite', ...
        'WIQ file wrote %d of %d components.',count,numel(values));
end
localPublish(tmpPath,pathValue);
end

function values=localReadInt16(pathValue,count)
fid=fopen(pathValue,'rb','ieee-le');
if fid<0
    error('sixgr:truth:ContinuousKeysightWIQOpen', ...
        'Cannot reopen WIQ file %s.',pathValue);
end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
values=fread(fid,Inf,'int16=>int16');
if numel(values)~=count
    error('sixgr:truth:ContinuousKeysightWIQExtent', ...
        'WIQ file has %d components; expected %d.',numel(values),count);
end
end

function localValidateVSAMAT(pathValue,expected,sampleCount)
inventory=whos('-file',pathValue);
names=string({inventory.name});
required=["Y","XDelta","InputCenter","InputZoom","XDomain"];
if ~all(ismember(required,names))
    error('sixgr:truth:ContinuousKeysightVSASchema', ...
        '89600 VSA MAT is missing required case-sensitive variables.');
end
loaded=load(pathValue,required{:});
if ~isa(loaded.Y,'single') || ~isequal(size(loaded.Y),[sampleCount 1]) || ...
        ~isequal(loaded.Y,expected.Y) || loaded.XDelta~=expected.XDelta || ...
        loaded.InputCenter~=expected.InputCenter || ...
        loaded.InputZoom~=1 || loaded.XDomain~=2
    error('sixgr:truth:ContinuousKeysightVSARoundtrip', ...
        '89600 VSA MAT readback differs from the packaged waveform contract.');
end
end

function localRefuseArtifacts(paths)
for pathValue=reshape(string(paths),1,[])
    if isfile(pathValue)
        error('sixgr:truth:ContinuousKeysightRefusesOverwrite', ...
            'Continuous Keysight packaging refuses to overwrite %s.',pathValue);
    end
end
end

function localPublish(sourcePath,destinationPath)
sixgr.util.ensureFolder(fileparts(char(string(destinationPath))));
[ok,message,identifier]=copyfile(sourcePath,destinationPath,'f');
if ~ok
    error('sixgr:truth:ContinuousKeysightPublish', ...
        'Cannot publish artifact (%s): %s',identifier,message);
end
sourceInfo=dir(sourcePath);
destinationInfo=dir(destinationPath);
if isempty(sourceInfo) || isempty(destinationInfo) || ...
        sourceInfo.bytes~=destinationInfo.bytes || ...
        localFileSHA256(sourcePath)~=localFileSHA256(destinationPath)
    error('sixgr:truth:ContinuousKeysightPublishMismatch', ...
        'Published artifact differs from its validated temporary source.');
end
end

function folder=localCanonicalFolder(pathValue)
folder=localAbsolutePath(pathValue);
if ~isfolder(folder)
    error('sixgr:truth:ContinuousKeysightSourceRunMissing', ...
        'Source run folder does not exist: %s',folder);
end
end

function pathOut=localAbsolutePath(pathValue)
pathOut=char(string(pathValue));
javaFile=java.io.File(pathOut);
pathOut=char(javaFile.getCanonicalPath());
end

function pathOut=localResolveChild(root,relative)
relative=replace(string(relative),'/',filesep);
pathOut=char(fullfile(root,relative));
rootKey=lower(replace(string(localAbsolutePath(root)),"\","/"));
pathKey=lower(replace(string(localAbsolutePath(pathOut)),"\","/"));
if ~startsWith(pathKey,rootKey+"/") || ~isfile(pathOut)
    error('sixgr:truth:ContinuousKeysightSourcePathEscape', ...
        'Source artifact is missing or outside the source run: %s',pathOut);
end
end

function relative=localRelativePath(root,pathValue)
root=replace(string(localAbsolutePath(root)),"\","/");
pathValue=replace(string(localAbsolutePath(pathValue)),"\","/");
if startsWith(lower(pathValue),lower(root+"/"))
    relative=extractAfter(pathValue,strlength(root)+1);
else
    relative=pathValue;
end
end

function hash=localFileSHA256(pathValue)
hash=lower(string(sixgr.util.sha256File(char(string(pathValue)))));
end

function value=localLogical(raw)
if islogical(raw)
    value=raw;
elseif isnumeric(raw)
    value=raw~=0;
else
    value=ismember(lower(strtrim(string(raw))),["true","1","yes","pass"]);
end
end

function localDeleteIfExists(pathValue)
try
    if isfile(pathValue), delete(pathValue); end
catch
end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('sixgr:truth:ContinuousKeysightPathType', ...
        'Continuous Keysight package paths must be text scalars.');
end
end
