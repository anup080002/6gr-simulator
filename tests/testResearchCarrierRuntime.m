function ok = testResearchCarrierRuntime()
%TESTRESEARCHCARRIERRUNTIME YAML-owned custom carrier and runtime provenance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
path=fullfile(pwd,'simulator','configs','bands','band_7ghz_400mhz_research.yaml');
raw=sixgr.lls6g.config.readConfigFile(path);
sixgr.lls6g.config.validateScenarioConfig(raw,'AllowPartial',true,'Context',path);
frame=sixgr.phy.FrameStructureEngine(raw,'FrameCoreOnly',true);
assert(frame.FrequencyRange=="CUSTOM" && ~frame.CarrierGrid.StandardNR);
assert(frame.CenterFrequencyHz==raw.frequency.center_frequency_hz);
assert(frame.BandwidthHz==raw.frequency.bandwidth_hz);
assert(frame.NRB==raw.frequency.n_size_grid);
assert(frame.FFTSize==raw.waveform.explicit_fft_size);
assert(frame.SampleRate_Hz==raw.waveform.explicit_sample_rate_hz);
assert(frame.CarrierGrid.OccupiedBandwidthHz== ...
    12*raw.frequency.n_size_grid*raw.frame.scs_khz*1e3);
assert(frame.CarrierGrid.OccupiedBandwidthHz<=frame.BandwidthHz);
assert(frame.CarrierGrid.MinimumLowGuardbandHz==raw.frequency.minimum_low_guardband_hz);
assert(frame.CarrierGrid.MinimumHighGuardbandHz==raw.frequency.minimum_high_guardband_hz);

cfg=raw;
cfg.phy.frameStructure=frame.toStruct();
cfg.phy.duplex.mode=raw.frequency.duplex_mode;
cfg.phy.duplex.tddCommon=raw.frame.tdd_common;
cfg.phy.schedulingTiming.k1SelectionPolicy=raw.tdd_timing.k1_selection_policy;
[snapshot,carriers]=sixgr.phy.frame.FrameRuntimeStateBuilder.build(cfg);
cc=snapshot.ComponentCarriers(1);
assert(cc.ResearchMode && ~cc.StandardNR && cc.FrequencyRange=="CUSTOM");
assert(~cc.DLCarrierGrid.StandardNR && ~cc.ULCarrierGrid.StandardNR);
assert(cc.DLCarrierGrid.MinimumLowGuardbandHz==raw.frequency.minimum_low_guardband_hz);
assert(cc.ULCarrierGrid.MinimumHighGuardbandHz==raw.frequency.minimum_high_guardband_hz);
assert(all([cc.BWPs.ResearchMode]) && ~any([cc.BWPs.StandardNR]));
assert(all([cc.BWPs.NSizeBWP]==raw.frequency.n_size_grid));
assert(all([cc.BWPs.SCSKHz]==raw.frame.scs_khz));
assert(all([cc.BWPs.CarrierSCSKHz]==raw.frame.scs_khz));

% Reconstruct from serialized runtime state without losing opt-in/identity.
cfg.phy.frame.componentCarriers=jsondecode(jsonencode(snapshot.ComponentCarriers));
[replayed,~]=sixgr.phy.frame.FrameRuntimeStateBuilder.build(cfg);
assert(replayed.ComponentCarriers.ResearchMode && ...
    ~replayed.ComponentCarriers.StandardNR);
assert(isequal(replayed.DefaultIdentity,snapshot.DefaultIdentity));

baseline=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    'simulator','configs','scenarios','dl_4ghz_baseline.yaml'));
wrongClass=baseline.toStruct();
wrongClass.frequency.research_mode=true;
localThrows(@()sixgr.lls6g.config.validateScenarioConfig(wrongClass), ...
    "sixgr:lls6g:config:ResearchCarrierScope");
badGuard=raw;
badGuard.frequency.minimum_low_guardband_hz=raw.frequency.bandwidth_hz;
localThrows(@()sixgr.phy.FrameStructureEngine(badGuard,'FrameCoreOnly',true), ...
    "sixgr:phy:frame:CustomGridGuardbandExceedsBandwidth");

noOptIn=raw;
noOptIn.frequency.custom_frequency_override_allowed=false;
localThrows(@()sixgr.phy.FrameStructureEngine(noOptIn,'FrameCoreOnly',true), ...
    "sixgr:phy:FrameStructureEngine:CustomGridRequiresOptIn");
standard=raw;
standard.frequency.research_mode=false;
localThrows(@()sixgr.phy.FrameStructureEngine(standard,'FrameCoreOnly',true), ...
    "sixgr:phy:frame:UnsupportedBandwidthSCSCombination");
forged=carriers{1}.toStruct();
forged.ResearchMode=false;
bwps={carriers{1}.configuredBWP(0,"DL"),carriers{1}.configuredBWP(0,"UL")};
localThrows(@()sixgr.phy.frame.ComponentCarrierConfig(forged,bwps), ...
    "sixgr:phy:frame:InvalidFrequencyRange");
forged.ResearchMode=true;
forged.DuplexMode="FDD";
localThrows(@()sixgr.phy.frame.ComponentCarrierConfig(forged,bwps), ...
    "sixgr:phy:frame:ResearchCarrierTDDOnly");
bwp=bwps{1}.toStruct();
bwp.SwitchActivationTime=bwp.ConfiguredActivationTick;
bwp.ResearchMode=false;
localThrows(@()sixgr.phy.frame.BWPConfig(bwp,cc.DLCarrierGrid), ...
    "sixgr:phy:frame:InvalidFrequencyRange");
ok=true;
fprintf('RESEARCH_CARRIER_RUNTIME_PASS frequency=%g bandwidth=%g Fs=%g standard_nr=0 link_run_executed=0\n', ...
    frame.CenterFrequencyHz,frame.BandwidthHz,frame.SampleRate_Hz);
end

function localThrows(action,identifier)
try
    action();
catch cause
    assert(string(cause.identifier)==identifier, ...
        'Expected %s, received %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',identifier);
end
