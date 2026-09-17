function ok=testResearchULCodedWaveform()
% Actual full-width Qm=10 UL coding/OFDM and independent receive reconstruction.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures', ...
    'research_ul_coded_waveform.yaml'));
s=scfg.toStruct();
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
slot=find(arrayfun(@(x)frame.IsULAllocation(x,s.research_ul.symbol_allocation), ...
    0:frame.SlotsPerFrame-1),1)-1;
assert(~isempty(slot));
a=sixgr.phy.ul.research.PUSCHLink.allocation(scfg,slot);
assert(a.Qm==10 && a.Modulation=="1024QAM" && ~a.StandardNR);
assert(a.G==a.LayerDataRE*10*a.NumLayers);
assert(a.TransportBlockSize==nrTBS('1024QAM',a.NumLayers, ...
    s.research_ul.num_prbs,a.NREPerPRB,a.TargetCodeRate,0));
assert(abs(norm(a.Precoder,'fro')^2-1)<1e-12);
tb=int8(randi([0 1],a.TransportBlockSize,1));
tx=sixgr.phy.ul.research.PUSCHLink.transmit(scfg,slot,tb);
assert(numel(tx.Codeword)==a.G && size(tx.Waveform,2)==a.NumLayers);
assert(isequal(size(tx.Grid),[frame.NRB*12 frame.SymbolsPerSlot a.NumLayers]));
% SNR authority is average transmitted data-RE EPRE per receive port on an
% explicitly identity AWGN channel; use the measured OFDM noise transform.
dataPower=mean(abs(tx.Grid(a.DataIndices)).^2,'all');
for referenceSNRdB=s.simulation.snr_db+reshape(s.simulation.snr_sweep_offsets_db,1,[])
noiseGridVariance=dataPower/10^(referenceSNRdB/10);
noiseSampleVariance=noiseGridVariance/tx.OFDM.SampleToGridNoiseVarianceGain;
noise=sqrt(noiseSampleVariance/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
rx=sixgr.phy.ul.research.PUSCHLink.receive(scfg,slot,tx.Waveform+noise);
assert(rx.CRCPass && isequal(rx.TransportBlock,tb), ...
    'Research full-width 1024-QAM UL must decode the exact transmitted TB.');
assert(numel(rx.CodewordLLR)==a.G && all(isfinite(rx.CodewordLLR)));
assert(size(rx.ChannelEstimate,1)==frame.NRB*12 && ...
    size(rx.ChannelEstimate,2)==frame.SymbolsPerSlot);
assert(rx.NoiseVariance>0 && rx.NoiseSource=="received_DMRS_nrChannelEstimate");
evm=sqrt(mean(abs(rx.EqualizedSymbols(:)-tx.LayerSymbols(:)).^2)/ ...
    mean(abs(tx.LayerSymbols(:)).^2));
if referenceSNRdB==40
    assert(evm<0.03,'Research UL high-SNR EVM regression.');
end
assert(evm<1.5*10^(-referenceSNRdB/20), ...
    'Research UL EVM exceeds the declared AWGN/channel-estimation error budget.');
fprintf('RESEARCH_UL_CODED_WAVEFORM_POINT Qm=%d G=%d TBS=%d layers=%d EVM=%g measured_noise=%g reference_noise=%g reference_SNR_dB=%g integrated_TDD=0\n', ...
    a.Qm,a.G,a.TransportBlockSize,a.NumLayers,evm,rx.NoiseVariance,noiseGridVariance,referenceSNRdB);
end
% Wrong receive-only identity must not recover the transmitted payload.
wrongIdentity=s; wrongIdentity.research_ul.rnti=s.research_ul.rnti+1;
wrongRx=sixgr.phy.ul.research.PUSCHLink.receive(wrongIdentity,slot,tx.Waveform+noise);
assert(~wrongRx.CRCPass && ~isequal(wrongRx.TransportBlock,tb));
% Standard receiver and procedure guards remain fail-closed.
localThrows(@()sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation('1024QAM'), ...
    'sixgr:pusch:UnsupportedModulation');
bad=s; bad.research_ul.uci_enabled=true;
localThrows(@()sixgr.phy.ul.research.PUSCHLink.allocation(bad,slot), ...
    'sixgr:research:UnsupportedULProcedure');
bad=s; bad.meta.research_class='baseline_benchmark';
localThrows(@()sixgr.phy.ul.research.PUSCHLink.allocation(bad,slot), ...
    'sixgr:research:ExplicitOptInRequired');
localThrows(@()sixgr.phy.ul.research.PUSCHLink.allocation(s,0), ...
    'sixgr:research:ULSlotRequired');
ok=true;
fprintf('RESEARCH_UL_CODED_WAVEFORM_PASS independent_receive_identity_rejection=1 integrated_TDD=0\n');
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
