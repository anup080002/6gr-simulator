function ok=testResearchPhysicalArray()
% Physical array, reciprocal path gains, total power and four-layer coding.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs','scenarios', ...
    'lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml'));
s=scfg.toStruct(); frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
link=sixgr.phy.research.PhysicalArrayLink.build(s,frame.SampleRate_Hz);
assert(isequal(link.TxElements,[64 4]) && isequal(link.RxElements,[4 64]));
assert(isequal(link.Manifest.GNBArray.Size,[8 4 2 1 1]));
assert(isequal(link.Manifest.UEArray.Size,[2 1 2 1 1]));
assert(string(link.Manifest.GNBArray.Element)=="38.901");
for d=1:2
    w=link.Weights{d};
    assert(norm(w*w'-eye(4),'fro')<1e-12 && all(sum(abs(w).^2,1)>0));
end
% Prove the UL channel is the same physical realization with reversed ports.
forward=clone(link.Channels{1}); reverse=clone(link.Channels{2});
forward.ChannelFiltering=false; reverse.ChannelFiltering=false;
forward.NumTimeSamples=1; reverse.NumTimeSamples=1;
g=forward(); u=reverse();
assert(isequal(size(g),[1 size(g,2) 64 4]));
assert(max(abs(u-permute(g,[1 2 4 3])),[],'all')<1e-12);
assert(any(abs(g(:))>0));
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(21,'twister');
for d=1:2
    x=randn(512,4)+1j*randn(512,4);
    [y,physical,e]=sixgr.phy.research.PhysicalArrayLink.apply(link,d,x);
    assert(isequal(size(y),[512 link.RxElements(d)]));
    assert(size(physical,2)==link.TxElements(d) && all(isfinite(y),'all'));
    assert(e.ArrayProjectionRelativeEnergyError<1e-11);
end
% Exact native reference geometry and CSV-backed joint DL/UL figure. These
% are not receiver angle estimates or beam/TCI qualification. Publication
% must leave both live channel states unchanged.
base=fullfile(pwd,'results','component_validation');
if ~isfolder(base), mkdir(base); end
folder=tempname(base); mkdir(folder);
before={clone(link.Channels{1}),clone(link.Channels{2})};
sixgr.phy.research.PhysicalArrayLink.export(folder,link,true);
csvPath=fullfile(folder,link.Manifest.ClusterAnglesCSV);
angles=sixgr.util.csvReadTable(csvPath,'TextType','string');
assert(~any(angles.ReceiverMeasured) && ~any(angles.UsedForBeamSelection));
directions=["DL","UL"];
for d=1:2
    native=info(before{d}); rows=angles(angles.Direction==directions(d),:);
    assert(isequal(rows.NativeClusterIndex0,(0:numel(native.PathDelays)-1).'));
    expected=[native.PathDelays(:),native.AveragePathGains(:),native.AnglesAoA(:), ...
        native.AnglesAoD(:),native.AnglesZoA(:),native.AnglesZoD(:)];
    assert(isequal(table2array(rows(:,{'PathDelay_s','AveragePathGain_dB', ...
        'AoA_deg','AoD_deg','ZoA_deg','ZoD_deg'})),expected));
    probe=complex(zeros(32,link.TxElements(d)));
    expectedSamples=before{d}(probe); actualSamples=link.Channels{d}(probe);
    assert(isequal(expectedSamples,actualSamples),'Export must not execute/reset the channel.');
end
dl=angles(angles.Direction=="DL",:); ul=angles(angles.Direction=="UL",:);
assert(isequal(dl.AoA_deg,ul.AoD_deg) && isequal(dl.AoD_deg,ul.AoA_deg) && ...
    isequal(dl.ZoA_deg,ul.ZoD_deg) && isequal(dl.ZoD_deg,ul.ZoA_deg));
lineage=jsondecode(fileread(fullfile(folder,'beamforming','image','cdl_cluster_angles.source.json')));
assert(string(lineage.SourceSHA256)==sixgr.phy.waveform.WaveformHash.file(csvPath) && ...
    lineage.SourceRows==height(angles) && ~lineage.ReceiverMeasured);
assert(isfile(fullfile(folder,'beamforming','image','cdl_cluster_angles.png')));
fprintf('RESEARCH_CDL_ANGLE_EXPORT_PASS native_reference=1 joint_DL_UL=1 unchanged_channel=1 folder=%s\n',folder);
bad=s; bad.research_spatial.gnb_dft_horizontal=[0 0 0 1];
localThrows(@()sixgr.phy.research.PhysicalArrayLink.build(bad,frame.SampleRate_Hz), ...
    'sixgr:research:NonOrthogonalArrayPorts');
bad=s; bad.channels.doppler_hz=1;
localThrows(@()sixgr.phy.research.PhysicalArrayLink.build(bad,frame.SampleRate_Hz), ...
    'sixgr:research:UnsupportedSpatialPolicy');
% Independently qualify the four-layer modulation/coding adapter on identity
% AWGN before combining it with the new array channel. Not the 30 dB result.
for direction=["DL","UL"]
    fixture=s; name="research_"+lower(direction);
    fixture.(name).num_prbs=8;
    if direction=="DL", slot=0; else, slot=4; end
    a=sixgr.phy.research.SharedChannelLink.allocation(fixture,slot,direction);
    assert(a.NumLayers==4 && a.Qm==10 && isscalar(a.TransportBlockSize));
    tb=int8(randi([0 1],a.TransportBlockSize,1));
    tx=sixgr.phy.research.SharedChannelLink.transmit(fixture,slot,tb,direction);
    noiseVariance=(1/a.NumLayers)/1e4/tx.OFDM.SampleToGridNoiseVarianceGain;
    noise=sqrt(noiseVariance/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
    rx=sixgr.phy.research.SharedChannelLink.receive(fixture,slot,tx.Waveform+noise,direction);
    assert(rx.CRCPass && isequal(rx.TransportBlock,tb));
    fprintf('FOUR_LAYER_CODED_COMPONENT_PASS direction=%s reference_SNR_dB=40 TBS=%d\n',direction,numel(tb));
end
ok=true;
fprintf('RESEARCH_PHYSICAL_ARRAY_PASS reciprocal_paths=1 energy_preserved=1 gnb_elements=64 ue_elements=4 layers=4\n');
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
