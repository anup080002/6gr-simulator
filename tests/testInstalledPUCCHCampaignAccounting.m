function ok=testInstalledPUCCHCampaignAccounting()
% TEST-ONLY event fixtures exercise accounting, not physical performance.
p=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_installed_pucch_development.yaml');
empty=sixgr.phy.pucch.summarizeInstalledReceiverCampaign(table(),p);
assert(all(empty.IndependentEpisodes==0)&&all(isnan(empty.Estimate))&& ...
    all(empty.StatisticalDecision=="PENDING_FIXED_SAMPLE"));
n=4; seq=(1:n).';
e=table("test_contract_"+seq,repmat(string({p.cases.id}).',2,1),seq,ceil(seq/2), ...
    p.seed_base+(seq-1)*p.seed_stride,p.seed_base+(seq-1)*p.seed_stride+p.noise_seed_offset, ...
    logical(mod(seq,2)==0),repmat(string(p.scope),n,1),ones(n,1),false(n,1), ...
    [0;NaN;0;NaN],[NaN;0;NaN;0], ...
    'VariableNames',{'EpisodeID','CaseID','Sequence','Replicate','ChannelSeed','NoiseSeed', ...
    'SignalPresent','Scope','IndependentWaveformCount','HARQBitsAreIndependentTrials', ...
    'FalseAcceptanceEpisode','CompleteUCIErrorEpisode'});
partial=sixgr.phy.pucch.summarizeInstalledReceiverCampaign(e(1:2,:),p);
assert(all(isnan(partial.CIUpper))&&~any(partial.FinalFixedSampleLook));
s=sixgr.phy.pucch.summarizeInstalledReceiverCampaign(e,p);
expected=1-(p.family_alpha/4)^(1/2);
assert(all(abs(s.CIUpper-expected)<1e-12) && all(s.CILower==0) && ...
    all(s.StatisticalDecision=="INCONCLUSIVE")&&~any(s.DetectorQualified)&&~any(s.ScenarioAccepted));
f=e; f.CompleteUCIErrorEpisode(f.SignalPresent)=1;
s=sixgr.phy.pucch.summarizeInstalledReceiverCampaign(f,p);
assert(s.EventCount(2)==2&&s.StatisticalDecision(2)=="BOUND_EXCEEDS_CONFIGURED_LIMIT");
bad=e; bad.NoiseSeed(3)=bad.NoiseSeed(1); reject(bad,p);
bad=e; bad.EpisodeID(3)=bad.EpisodeID(1); reject(bad,p);
bad=e; bad.IndependentWaveformCount(2)=17; reject(bad,p);
bad=e; bad.HARQBitsAreIndependentTrials(2)=true; reject(bad,p);
bad=e; bad.SignalPresent=double(bad.SignalPresent); bad.SignalPresent(2)=2; reject(bad,p);
bad=e; bad.SignalPresent=double(bad.SignalPresent); bad.SignalPresent(2)=NaN; reject(bad,p);
bad=e; bad.FalseAcceptanceEpisode(1)=NaN; reject(bad,p);
bad=e; bad.CompleteUCIErrorEpisode(1)=0; reject(bad,p);
bad=e; bad.CaseID(2)=bad.CaseID(1); reject(bad,p);
reject(e([1 3 2 4],:),p);
reject([e;e(1,:)],p);
ok=true;
end
function reject(e,p)
caught=false;
try, sixgr.phy.pucch.summarizeInstalledReceiverCampaign(e,p);
catch err
    assert(strcmp(err.identifier,'sixgr:pucch:InvalidCampaignPopulation'),err.getReport());
    caught=true;
end
assert(caught,'test:InvalidPopulationAccepted','Nonbinary or inconsistent evidence was accepted.');
end
