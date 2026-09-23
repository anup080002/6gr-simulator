function ok = testStandaloneAWGNReferenceEnergy()
% A fixed-link operating point must honor the same fixed Es as shared PHY.
% No access/control acceptance is claimed by this isolated data fixture.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.noiseOperatingMode = 'standalone_awgn_snr_argument';
cfg.run.interferenceExecutionMode = 'none';
cfg.integration.run_mode = 'FIXED_SNR_SWEEP';
cfg.integration.configured_snr_is_link_authority = true;
cfg.outputs.saveCSV = false; cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = 'AWGN'; cfg.channel.awgnOnly = true;
cfg.phy.ssb.enable = false;
for direction = ["DL", "UL"]
    if direction=="DL", key='pdsch'; else, key='pusch'; end
    cfg.phy.(key).executionProfile = 'phy_calibration';
    cfg.phy.(key).nLayers=1; cfg.phy.(key).numLayers=1;
    cfg.phy.(key).mcsIndex=4; cfg.phy.(key).mcsTable='qam64_table1';
    cfg.phy.(key).modulation='QPSK'; cfg.phy.(key).codeRate=308/1024;
    cfg.phy.(key).prbSet=0:5; cfg.phy.(key).symbolAllocation=[2 12];
    cfg.phy.(key).mappingType='A'; cfg.phy.(key).dmrs.portSet=0;
    for referenceEnergy = [.25 1]
        cfg.channel.awgnReferenceREEnergy = referenceEnergy;
        if direction=="DL"
            out=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',1,'SNR_dB',30);
        else
            out=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',1,'SNR_dB',30);
        end
        T=out.TrialTable;
        assert(height(T)==1 && T.DecodeAttempted, ...
            'The noise comparison requires an actual waveform receiver trial.');
        fprintf('STANDALONE_REFERENCE direction=%s configured=%g applied=%g gridNoise=%g\n', ...
            direction,referenceEnergy,T.SignalEnergyPerOccupiedRE,T.ReplayGridNoiseVariance);
        assert(T.SignalEnergyPerOccupiedRE==referenceEnergy, ...
            'test:StandaloneAWGNReferenceRecalibrated', ...
            'Standalone noise ignored channel.awgnReferenceREEnergy.');
        assert(abs(T.ReplayGridNoiseVariance-referenceEnergy*1e-3)<1e-12);
    end
end
ok=true;
end
