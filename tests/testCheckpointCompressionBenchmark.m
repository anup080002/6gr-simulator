function ok=testCheckpointCompressionBenchmark(compressionModes,root,fullBand)
% Bounded native-OFDM/handle serialization benchmark, NOT the 100 MHz
% production-state benchmark or a promise of full-slot speedup.
if nargin<1, compressionModes=[true false]; end
if nargin<2
    root=fullfile(pwd,'logs','lls_repairs',['checkpoint_compression_' char(java.util.UUID.randomUUID)]);
end
if nargin<3, fullBand=false; end
validateattributes(compressionModes,{'logical'},{'vector','nonempty'});
validateattributes(fullBand,{'logical'},{'scalar'});
if ~isfolder(root), mkdir(root); end
nprb=24; ports=4;
if fullBand, nprb=273; ports=64; end
carrier=nrCarrierConfig('NSizeGrid',nprb,'SubcarrierSpacing',30);
rs=RandStream('mt19937ar','Seed',476201);
grid=complex(randn(rs,nprb*12,14,ports),randn(rs,nprb*12,14,ports));
samples=nrOFDMModulate(carrier,grid);
clear grid
waveformHash=sixgr.phy.waveform.WaveformHash.runtimeArray(samples);
ofdmInfo=nrOFDMInfo(carrier);
owner=MatSaveLoadProbe(samples);
payload=struct('Owner',owner,'SharedOwner',owner,'Waveform',samples, ...
    'Counter',46,'RNG',rs.State,'Source',"native_OFDM_checkpoint_compression_fixture");
rows=struct([]);
for enabled=compressionModes
    path=fullfile(root,"compression_"+string(enabled)+".mat");
    phase("save",enabled);
    prior=memoryBytes(); t=tic;
    sixgr.util.matSave(path,struct('payload',payload),'UseArtifactStore',false, ...
        'ForceV73',true,'Compression',enabled);
    saveSeconds=toc(t); afterSave=memoryBytes();
    phase("restore",enabled);
    t=tic; restored=load(path); loadSeconds=toc(t); afterLoad=memoryBytes();
    phase("verify",enabled);
    assert(isequaln(restored.payload.Waveform,payload.Waveform) && ...
        isequal(restored.payload.Owner.Samples,owner.Samples) && ...
        restored.payload.Owner==restored.payload.SharedOwner && ...
        isequal(restored.payload.RNG,payload.RNG));
    info=dir(path);
    row=struct('CompressionEnabled',enabled,'NSizeGrid',nprb,'WaveformPorts',ports, ...
        'SampleRateHz',ofdmInfo.SampleRate,'SampleCount',size(samples,1), ...
        'Seed',476201,'WaveformSHA256',waveformHash, ...
        'FileBytes',info.bytes, ...
        'SaveAndVerifiedPublishSeconds',saveSeconds,'LoadSeconds',loadSeconds, ...
        'MemoryBeforeBytes',prior,'MemoryAfterSaveBytes',afterSave, ...
        'MemoryAfterLoadBytes',afterLoad, ...
        'MemoryScope',"boundary_snapshots_not_peak_sampling", ...
        'RoundTripExact',true, ...
        'Scope',"bounded_native_OFDM_fixture_not_full_runtime_checkpoint");
    if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    clear restored
end
sixgr.util.csvWriteTable(fullfile(root,'compression_benchmark.csv'),struct2table(rows));
% The default stays compressed regardless of this small fixture's outcome.
fprintf('CHECKPOINT_COMPRESSION_BENCHMARK_PASS output=%s\n',root);
ok=true;
phase("complete",compressionModes(end));
    function phase(name,enabled)
        sixgr.util.jsonWrite(fullfile(root,'benchmark_phase.json'),struct( ...
            'Phase',name,'CompressionEnabled',enabled,'PID',feature('getpid')));
    end
end
function value=memoryBytes()
value=NaN;
if ispc, info=memory; value=double(info.MemUsedMATLAB); end
end
