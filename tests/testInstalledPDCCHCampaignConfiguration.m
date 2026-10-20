function ok=testInstalledPDCCHCampaignConfiguration()
% Installed configuration and TX construction only, not a physical population.
p=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_installed_pdcch_campaign_development.yaml');
sixgr.phy.pdcch.validateInstalledReceiverCampaign(p);
bad=p; bad.cases(1).transmitter=p.cases(2).transmitter; reject(bad);
bad=p; bad.cases=bad.cases(2:3); reject(bad);
bad=p; bad.cases(4)=bad.cases(2); bad.cases(4).id='duplicate'; reject(bad);
bad=p; bad.cases(2).absolute_slot0=41; reject(bad); % no paired H0 context
bad=p; bad.noise_seed_offset=bad.seed_stride; reject(bad);
bad=p; bad.seed_base=2^32-1; reject(bad);
bad=p; bad.stage='frozen_qualification'; reject(bad);
bad=p; bad.stage='frozen_qualification'; bad.episodes_per_case=1000;
bad.development_seeds=[bad.development_seeds(:);bad.seed_base]; reject(bad);
bad=p; bad.cases(2).transmitter.fields.mcs=NaN; reject(bad);
bad=p; bad.timing_boundary='transmitted_timing_oracle'; reject(bad);
bad=p; bad.UnknownFallback=true; reject(bad);
base=sixgr.lls6g.config.loadScenarioConfig(p.scenario_path);
seeded=sixgr.link.seedInstalledControlScenario(base,p,p.seed_base,"PDCCH");
assert(base.ConfigHash~=seeded.ConfigHash);
folder=fullfile(pwd,'results','lls','installed_pdcch_configuration', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))); mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(seeded,folder);
assert(cfg.run.seed==p.seed_base&&cfg.channel.seed==p.seed_base);
for path=["rf.frontend.oscillator.seed","rf.frontend.phase_noise.seed"]
    assert(sixgr.util.structGet(cfg,path)==p.seed_base,'test:RFSeedNotBound');
end
[c0,t0]=sixgr.link.buildConfiguredPDCCHCampaignEpisode(cfg,p.cases(1));
assert(isempty(t0));
for k=2:3
    [c,tx]=sixgr.link.buildConfiguredPDCCHCampaignEpisode(cfg,p.cases(k));
    assert(isequal(c.phy.pdcch,c0.phy.pdcch),'test:TXNarrowedReceiveSearch');
    assert(tx.SampleRateHz==122.88e6&&size(tx.TransmitSamples,2)==64);
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(c,p.cases(k).transmitter.dci_format);
    decoded=sixgr.phy.pdcch.DCIParser.parse(tx.Tx.DCIBits,context);
    assert(decoded.Fields.mcs==p.cases(k).transmitter.fields.mcs);
end
bad=p.cases(2); bad.transmitter.fields.unknown_payload_oracle=1;
caught=false;
try, sixgr.link.buildConfiguredPDCCHCampaignEpisode(cfg,bad);
catch err
    assert(strcmp(err.identifier,'sixgr:pdcch:InvalidCampaignTransmitter'),err.getReport()); caught=true;
end
assert(caught);
save(fullfile(folder,'configuration_check.mat'),'base','seeded','p');
ok=true;
end
function reject(p)
caught=false;
try, sixgr.phy.pdcch.validateInstalledReceiverCampaign(p);
catch err
    assert(strcmp(err.identifier,'sixgr:pdcch:InvalidInstalledCampaign'),err.getReport()); caught=true;
end
assert(caught,'test:InvalidCampaignAccepted');
end
