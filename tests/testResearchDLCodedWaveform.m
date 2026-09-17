function ok=testResearchDLCodedWaveform()
% Research DL uses the actual 1024-QAM native PDSCH modulation and RE map.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures', ...
    'research_ul_coded_waveform.yaml'));
s=scfg.toStruct();
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
slot=find(arrayfun(@(x)frame.IsDLAllocation(x,s.research_dl.symbol_allocation), ...
    0:frame.SlotsPerFrame-1),1)-1;
assert(~isempty(slot));
a=sixgr.phy.research.SharedChannelLink.allocation(scfg,slot,"DL");
assert(a.Qm==10 && a.Modulation=="1024QAM" && ~a.StandardNR);
[nativeIndices,nativeInfo]=nrPDSCHIndices(a.Carrier,a.ReferenceGeometry);
assert(isequal(a.DataIndices,nativeIndices) && a.G==nativeInfo.G);
assert(a.TransportBlockSize==nrTBS('1024QAM',a.NumLayers, ...
    s.research_dl.num_prbs,nativeInfo.NREPerPRB,a.TargetCodeRate,0));
tb=int8(randi([0 1],a.TransportBlockSize,1));
tx=sixgr.phy.research.SharedChannelLink.transmit(scfg,slot,tb,"DL");
assert(isequal(tx.LayerSymbols,nrPDSCH(a.Carrier,a.ReferenceGeometry,tx.Codeword)));
assert(abs(norm(a.Precoder,'fro')^2-1)<1e-12);
dataPower=mean(abs(tx.Grid(a.DataIndices)).^2,'all');
for snr=s.simulation.snr_db+reshape(s.simulation.snr_sweep_offsets_db,1,[])
    nvGrid=dataPower/10^(snr/10);
    nvSample=nvGrid/tx.OFDM.SampleToGridNoiseVarianceGain;
    noise=sqrt(nvSample/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
    rx=sixgr.phy.research.SharedChannelLink.receive(scfg,slot,tx.Waveform+noise,"DL");
    assert(rx.CRCPass && isequal(rx.TransportBlock,tb));
    evm=sqrt(mean(abs(rx.EqualizedSymbols(:)-tx.LayerSymbols(:)).^2)/ ...
        mean(abs(tx.LayerSymbols(:)).^2));
    assert(evm<1.5*10^(-snr/20));
    fprintf('RESEARCH_DL_CODED_WAVEFORM_POINT Qm=%d G=%d TBS=%d layers=%d EVM=%g reference_SNR_dB=%g integrated_TDD=0\n', ...
        a.Qm,a.G,a.TransportBlockSize,a.NumLayers,evm,snr);
end
ok=true;
fprintf('RESEARCH_DL_CODED_WAVEFORM_PASS integrated_TDD=0\n');
end
