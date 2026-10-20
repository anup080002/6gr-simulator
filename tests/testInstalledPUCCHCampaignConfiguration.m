function ok=testInstalledPUCCHCampaignConfiguration()
% Configuration/ownership checks, not RF performance or a population.
p=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_installed_pucch_development.yaml');
sixgr.phy.pucch.validateInstalledReceiverCampaign(p);
bad=p; bad.cases(1).transmitter=p.cases(2).transmitter; reject(bad);
bad=p; bad.cases=bad.cases(1); reject(bad);
bad=p; bad.cases(3)=bad.cases(2); bad.cases(3).id='renamed_duplicate'; reject(bad);
bad=p; bad.noise_seed_offset=bad.seed_stride; reject(bad);
bad=p; bad.seed_base=2^32-1; reject(bad);
bad=p; bad.stage='frozen_qualification'; reject(bad); % too few episodes
bad=p; bad.stage='frozen_qualification'; bad.episodes_per_case=1000;
bad.development_seeds=[bad.development_seeds(:); bad.seed_base]; reject(bad);
bad=p; bad.cases(2).transmitter.control.k1=2; reject(bad);
bad=p; bad.cases(2).transmitter.harq_bits=[1 0 2]; reject(bad);
bad=p; bad.UnknownFallback=true; reject(bad);
base=sixgr.lls6g.config.loadScenarioConfig(p.scenario_path);
seeded=sixgr.link.seedInstalledPUCCHScenario(base,p,p.seed_base);
assert(seeded.ConfigHash~=base.ConfigHash);
folder=fullfile(pwd,'results','lls','installed_pucch_configuration', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(seeded,folder);
assert(cfg.run.seed==p.seed_base && cfg.channel.seed==p.seed_base);
for path=["rf.frontend.oscillator.seed","rf.frontend.phase_noise.seed"]
    assert(sixgr.util.structGet(cfg,path)==p.seed_base,'test:RFSeedNotBound');
end
[~,a0,c0,t0]=sixgr.link.buildConfiguredPUCCHEpisode(cfg,p.cases(1));
assert(isempty(t0)&&c0.HARQACKBits==2&&c0.SRBits==1&&c0.CSIPart1Bits==14);
[~,a1,c1,t1]=sixgr.link.buildConfiguredPUCCHEpisode(cfg,p.cases(2));
assert(c1.HARQACKBits==2&&c1.SRBits==1&&c1.CSIPart1Bits==14);
assert(a1.Resource.Digest==t1.Assignment.Resource.Digest && ...
    numel(t1.Serialization.Sequence1.Bits)==17 && ...
    t1.OFDMInfo.SampleRate==122.88e6 && t1.OFDMInfo.Nfft==4096);
% Payload changes cannot change the independently installed receiver context.
changed=p.cases(2); changed.transmitter.harq_bits=[0 1];
[~,a2,c2,t2]=sixgr.link.buildConfiguredPUCCHEpisode(cfg,changed);
assert(a2.Digest==a1.Digest&&c2.Digest==c1.Digest && ...
    ~isequal(t1.Serialization.Sequence1.Bits,t2.Serialization.Sequence1.Bits));
% Do not "repair" a valid missed-producer/layout mismatch before physical RX.
changed.transmitter.harq_bits=1;
[~,a3,c3,t3]=sixgr.link.buildConfiguredPUCCHEpisode(cfg,changed);
assert(a3.Digest==a1.Digest&&c3.Digest==c1.Digest && ...
    numel(t3.Serialization.Sequence1.Bits)==16);
% Illegal duplex allocation fails even for H0, before any waveform execution.
changed=p.cases(1); changed.absolute_slot0=0;
caught=false;
try, sixgr.link.buildConfiguredPUCCHEpisode(cfg,changed);
catch err
    assert(strcmp(err.identifier,'sixgr:pucch:IllegalEpisodeResource'),err.getReport());
    caught=true;
end
assert(caught);
save(fullfile(folder,'configuration_check.mat'),'base','seeded','p','a0','c0','a1','c1');
ok=true;
end
function reject(p)
caught=false;
try, sixgr.phy.pucch.validateInstalledReceiverCampaign(p);
catch err
    assert(strcmp(err.identifier,'sixgr:pucch:InvalidInstalledCampaign'),err.getReport());
    caught=true;
end
assert(caught,'test:InvalidCampaignAccepted');
end
