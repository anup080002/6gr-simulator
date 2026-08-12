function test_ia_awgn_snr_calibration()
%TEST_IA_AWGN_SNR_CALIBRATION Verify central active-RE SNR convention.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9102);
clean=repmat(b.Waveform,1,256);
for snr=[-20 -10 0 10]
    [~,noise]=sixgr.phy.ia.c0.channel.addNoiseForTargetSNR( ...
        clean,b,1,snr,9200+snr);
    [noisePower,~]=sixgr.phy.ia.c0.channel.measureActiveREPower( ...
        noise,b,0);
    measured=10*log10(1/noisePower);
    assert(abs(measured-snr)<=0.1, ...
        'SNR calibration error %.4f dB at requested %.1f dB.',measured-snr,snr);
end
fprintf('test_ia_awgn_snr_calibration: PASS\n');
end
