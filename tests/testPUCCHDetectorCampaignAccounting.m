function ok=testPUCCHDetectorCampaignAccounting()
% Declared statistical fixtures only. No physical episodes are generated.
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/pucch_tdd_detector_held_out.yaml');
p=sixgr.lls6g.config.readConfigFile(v.episode_policy_path);
seeds=validatePUCCHDetectorCampaignPolicy(v,p);
assert(numel(seeds)==600 && numel(unique(seeds))==600 && ...
    isempty(intersect(seeds,v.development_seeds)) && ~v.development_history_complete);
ep=p; ep.stage='held_out_campaign_episode'; ep.seed_base=seeds(1);
validatePUCCHDetectorEpisodePolicy(ep);
localReject(@()validatePUCCHDetectorPilotPolicy(ep),'test:PilotPolicy');
bad=v; bad.seed_base=p.seed_base;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignSeeds');
bad=v; bad.development_seeds=4702601;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignHistory');
bad=v; bad.development_seeds=[bad.development_seeds(:);bad.development_seeds(1)];
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignHistory');
bad=v; bad.seed_base=2^32-1;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignSeeds');
bad=v; bad.episodes=599;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignGates');
bad=v; bad.family_alpha=0.10;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignGates');
bad=v; bad.event_error_limit=0.02;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignGates');
bad=v; bad.hidden_override=true;
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignPolicy');
bad=v; bad.development_history_complete='false';
localReject(@()validatePUCCHDetectorCampaignPolicy(bad,p),'test:CampaignHistory');
empty=summarizePUCCHDetectorCampaign(v,p,table());
assert(all(empty.ExecutedEpisodes==0 & empty.UnavailableEpisodes==600 & ...
    empty.ConservativeFailureUpperBound==1 & ~empty.ConfidenceGatePassed & ~empty.DetectorQualified));
% These rows are mathematical test inputs, NOT generated PHY observations.
ids=string({p.cases.id}).'; count=numel(ids);
rows=table(repelem((1:v.episodes).',count),repmat(ids,v.episodes,1), ...
    repelem(seeds(:),count),zeros(v.episodes*count,1), ...
    'VariableNames',{'CampaignEpisode','CaseID','Seed','EventError'});
zero=summarizePUCCHDetectorCampaign(v,p,rows);
assert(all(zero.ConfidenceGatePassed & ~zero.DetectorQualified));
expected=-expm1(log(v.family_alpha/count)/v.episodes);
assert(all(abs(zero.ConservativeFailureUpperBound-expected)<1e-12));
one=rows; one.EventError(1)=1;
summary=summarizePUCCHDetectorCampaign(v,p,one);
assert(~summary.ConfidenceGatePassed(1) && all(summary.ConfidenceGatePassed(2:end)) && ...
    summary.ConservativeFailureUpperBound(1)>0.01);
% The execution driver must stop a frozen campaign as soon as even the
% best-case final confidence bound cannot pass.  One event is already
% terminal for this 600-episode/Bonferroni design.
bestCaseUpper=betaincinv(1-v.family_alpha/count,2,v.episodes-1);
assert(bestCaseUpper>v.event_error_limit);
missing=summarizePUCCHDetectorCampaign(v,p,rows(2:end,:));
assert(missing.ExecutedEpisodes(1)==599 && missing.UnavailableEpisodes(1)==1 && ...
    missing.ObservedEventErrors(1)==0 && ~missing.ConfidenceGatePassed(1));
localReject(@()summarizePUCCHDetectorCampaign(v,p,[rows;rows(1,:)]),'test:CampaignRows');
badRows=rows; badRows.Seed(1)=p.seed_base;
localReject(@()summarizePUCCHDetectorCampaign(v,p,badRows),'test:CampaignRows');
badRows=rows; badRows.EventError(1)=0.5;
localReject(@()summarizePUCCHDetectorCampaign(v,p,badRows),'test:CampaignRows');
badRows=rows; badRows.CaseID(1)="invented";
localReject(@()summarizePUCCHDetectorCampaign(v,p,badRows),'test:CampaignRows');
ok=true;
disp('DETECTOR_CAMPAIGN_ACCOUNTING_PASS: declared inputs; seed exclusions, missing episodes and unchanged confidence gates; RF episodes=0.');
end
function localReject(f,id)
try
    f();
catch err
    assert(string(err.identifier)==id,err.message);
    return;
end
error('test:CampaignMissingRejection','Expected %s.',id);
end
