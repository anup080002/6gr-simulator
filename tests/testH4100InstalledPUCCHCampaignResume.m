function ok=testH4100InstalledPUCCHCampaignResume()
% FOUR actual independently seeded physical episodes, not qualification.
% No mock RX outcomes. A physical error remains in the population.
p='simulator/configs/validation/h4_100_installed_pucch_development.yaml';
output=fullfile(pwd,'results','lls','installed_pucch_campaign');
tag=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
first=sixgr.link.runInstalledPUCCHReceiverCampaign(p,output,tag);
assert(first.CompletedEpisodes==2 && ~first.CollectionComplete && ~first.DetectorQualified);
root=string(first.RunFolder);
firstCommit=fullfile(root,'episodes','episode_00000001','completed.mat');
firstHash=string(sixgr.util.sha256File(firstCommit));
second=sixgr.link.runInstalledPUCCHReceiverCampaign(p,output,tag);
assert(second.CompletedEpisodes==4 && second.CollectionComplete && ~second.DetectorQualified && ...
    ~second.FixedSampleStatisticalDecisionEligible && ~second.NRConformanceQualified);
assert(string(sixgr.util.sha256File(firstCommit))==firstHash,'test:ResumeReplacedEpisode');
third=sixgr.link.runInstalledPUCCHReceiverCampaign(p,output,tag);
assert(isequaln(second,third),'test:CompletedCampaignReran');
events=readtable(fullfile(root,'reports','csv','receiver_episodes.csv'),'TextType','string');
assert(height(events)==4 && numel(unique(events.NoiseSeed))==4 && ...
    isequal(events.SignalPresent,logical([0;1;0;1])) && ...
    ~any(events.StatisticallyQualified) && all(events.IndependentWaveformCount==1));
% Even the final two-observation zero-error case cannot qualify 1% risk.
summary=readtable(fullfile(root,'reports','csv','qualification_status.csv'),'TextType','string');
assert(all(summary.FinalFixedSampleLook) && all(summary.CIUpper>0.01));
% Corrupt/incomplete fixtures are isolated metadata copies, never edits of
% the actual physical evidence. All must be refused before a new episode.
badTag=tag+"_incomplete_contract"; bad=fullfile(output,badTag);
mkdir(bad); copyfile(fullfile(root,'meta'),fullfile(bad,'meta'));
mkdir(fullfile(bad,'episodes','episode_00000001'));
reject(p,output,badTag);
badTag=tag+"_changed_input_contract"; bad=fullfile(output,badTag);
mkdir(bad); copyfile(fullfile(root,'meta'),fullfile(bad,'meta'));
inputs=dir(fullfile(bad,'meta','input_configs','*')); inputs=inputs(~[inputs.isdir]);
sixgr.util.writeTextFile(fullfile(inputs(1).folder,inputs(1).name),'TEST-ONLY CORRUPTED COPY');
reject(p,output,badTag);
fprintf('H4_INSTALLED_PUCCH_RESUME_PASS physical_episodes=4 qualified=0 folder=%s\n',root);
ok=true;
end
function reject(p,output,tag)
caught=false;
try, sixgr.link.runInstalledPUCCHReceiverCampaign(p,output,tag);
catch err
    assert(strcmp(err.identifier,'sixgr:pucch:InstalledCampaignIntegrity'),err.getReport());
    caught=true;
end
assert(caught,'test:CorruptCampaignResumed');
end
