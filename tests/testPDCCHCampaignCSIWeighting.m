function ok=testPDCCHCampaignCSIWeighting()
% Compatibility check of the legacy one-candidate campaign kernel only.
% Its known-noise/limited-search assumptions do NOT qualify installed H4.
% Use the same installed contextual profile as the existing phase tests;
% the mini-anchor's legacy profile cannot enter this stricter TX API.
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/master_geometry_based.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempdir);
strict=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(cfg);
context=sixgr.phy.pdcch.resolveDCIContext(strict,'1_0');
fixture=sixgr.phy.pdcch.PDCCHWaveformTrialEngine.createFixture(strict,context,4);
for present=[false true]
    options=struct('Seed',20261019,'Trial',1+double(present),'SNRdB',30, ...
        'Channel',"AWGN",'DopplerHz',0,'SignalPresent',present,'CFOHz',0, ...
        'TimingOffsetSamples',0,'PhaseNoiseStdRadians',0);
    out=sixgr.phy.pdcch.PDCCHWaveformTrialEngine.runCampaignTrial(fixture,options);
    assert(~out.FalseAlarm && ~out.MissedDetection && out.CorrectDetection==present);
end
ok=true; fprintf('PDCCH_CAMPAIGN_CSI_WEIGHTING_PASS scope=legacy_kernel_compatibility_only\n');
end
