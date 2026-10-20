function ok=testInstalledPDCCHCampaignAccounting()
% TEST-ONLY event fixtures check accounting; they are not PHY samples.
p=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_installed_pdcch_campaign_development.yaml');
s=sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(table(),p);
assert(all(s.IndependentEpisodes==0)&&all(isnan(s.Estimate)));
n=3; seq=(1:n).';
e=table("test_contract_"+seq,string({p.cases.id}).',seq,ones(n,1), ...
    p.seed_base+(seq-1)*p.seed_stride,p.seed_base+(seq-1)*p.seed_stride+p.noise_seed_offset, ...
    logical([0;1;1]),repmat(string(p.scope),n,1),ones(n,1),false(n,1), ...
    [0;NaN;NaN],[0;NaN;NaN],[NaN;0;0],[NaN;0;0],[0;1;1],[NaN;1;1], ...
    'VariableNames',{'EpisodeID','CaseID','Sequence','Replicate','ChannelSeed','NoiseSeed', ...
    'SignalPresent','Scope','IndependentWaveformCount','HypothesesAreIndependentTrials', ...
    'FalseCRCEpisode','FalseContextAcceptanceEpisode','MissedPayloadEpisode', ...
    'WrongPayloadAcceptanceEpisode','ReceiverAccepted','ExactPayloadRecovered'});
partial=sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(e(1:2,:),p);
assert(all(isnan(partial.CIUpper))&&~any(partial.FinalFixedSampleLook));
s=sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(e,p);
assert(all(abs(s.CIUpper-(1-p.family_alpha/6))<1e-12)&&all(s.CILower==0)&& ...
    all(s.StatisticalDecision=="INCONCLUSIVE")&&~any(s.DetectorQualified));
% A CRC pass rejected by context still counts as a false CRC on H0.
f=e; f.FalseCRCEpisode(1)=1;
s=sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(f,p);
assert(s.EventCount(1)==1);
% An actual decoded-but-wrong H1 payload is an error, not a successful sample.
f=e; f.ExactPayloadRecovered(2)=0; f.MissedPayloadEpisode(2)=1;
f.WrongPayloadAcceptanceEpisode(2)=1;
s=sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(f,p);
assert(s.EventCount(2)==1);
bad=e; bad.IndependentWaveformCount(1)=32; reject(bad,p);
bad=e; bad.HypothesesAreIndependentTrials(1)=true; reject(bad,p);
bad=e; bad.SignalPresent=double(bad.SignalPresent); bad.SignalPresent(2)=2; reject(bad,p);
bad=e; bad.SignalPresent=double(bad.SignalPresent); bad.SignalPresent(2)=NaN; reject(bad,p);
bad=e; bad.NoiseSeed(3)=bad.NoiseSeed(1); reject(bad,p);
bad=e; bad.EpisodeID(3)=bad.EpisodeID(1); reject(bad,p);
bad=e; bad.FalseContextAcceptanceEpisode(1)=1; reject(bad,p);
bad=e; bad.MissedPayloadEpisode(2)=NaN; reject(bad,p);
bad=e; bad.ExactPayloadRecovered(2)=0; reject(bad,p);
bad=e; bad.WrongPayloadAcceptanceEpisode(2)=1; reject(bad,p);
reject(e([1 3 2],:),p); reject([e;e(1,:)],p);
ok=true;
end
function reject(e,p)
caught=false;
try, sixgr.phy.pdcch.summarizeInstalledReceiverCampaign(e,p);
catch err
    assert(strcmp(err.identifier,'sixgr:pdcch:InvalidCampaignPopulation'),err.getReport());
    caught=true;
end
assert(caught,'test:InvalidPopulationAccepted');
end
