function ok=testSRSStandaloneScoringTiming()
% Standalone NMSE must score actual Hest without receive-branch averaging.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_result_richness.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[out,capture]=sixgr.link.runSRSChannelEstimation(cfg,'SNR_dB',30,'TrialIndex',1);
assert(out.Ok && out.NMSE_dB<out.ChannelNMSEThreshold_dB && ...
    out.ChannelNMSEScoring.NumReceiveAntennas==2 && ...
    out.ChannelNMSEScoring.NumSRSPorts==1 && ...
    ~out.ChannelNMSEScoring.GainOrPhaseFitted);
assert(capture.Replay.NMSEReferenceTimingOffset_samples==16 && ...
    contains(out.NMSEReferenceSource,'single_port_pilot_ratio'));
ref=sixgr.phy.waveform.ofdmDemodulate(capture.Tx.Carrier,capture.ScoringReferenceWaveform);
est=capture.Rx.Hest; K=size(est,1); L=size(est,2); R=size(est,3);
indices=double(capture.Tx.SRSIndices(:));
errorEnergy=0; referenceEnergy=0;
for r=1:R
    at=indices+(r-1)*K*L;
    h=ref(at)./capture.Tx.SRSSymbols(:);
    errorEnergy=errorEnergy+sum(abs(est(at)-h).^2);
    referenceEnergy=referenceEnergy+sum(abs(h).^2);
end
expected=10*log10(errorEnergy/referenceEnergy);
assert(abs(out.NMSE_dB-expected)<1e-10 && ...
    out.ChannelNMSEScoring.ComparedComplexValueCount==numel(indices)*R);
fprintf('SRS actual-Hest all-RX NMSE %.3f dB, %d complex pilot values.\n', ...
    out.NMSE_dB,out.ChannelNMSEScoring.ComparedComplexValueCount);
ok=true;
end
