function ok=testH4100InstalledPDCCHCampaignResume()
% THREE actual independently seeded full-search episodes, not qualification.
% Physical misses/errors are retained; this checks collection, not a pass target.
p='simulator/configs/validation/h4_100_installed_pdcch_campaign_development.yaml';
output=fullfile(pwd,'results','lls','installed_pdcch_campaign');
tag=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
first=sixgr.link.runInstalledPDCCHReceiverCampaign(p,output,tag);
assert(first.CompletedEpisodes==2&&~first.CollectionComplete&&~first.DetectorQualified);
root=string(first.RunFolder);
commit=fullfile(root,'episodes','episode_00000001','completed.mat');
hash=string(sixgr.util.sha256File(commit));
second=sixgr.link.runInstalledPDCCHReceiverCampaign(p,output,tag);
assert(second.CompletedEpisodes==3&&second.CollectionComplete&&~second.DetectorQualified&& ...
    ~second.FixedSampleStatisticalDecisionEligible&&~second.NRConformanceQualified);
assert(string(sixgr.util.sha256File(commit))==hash,'test:ResumeReplacedEpisode');
third=sixgr.link.runInstalledPDCCHReceiverCampaign(p,output,tag);
assert(isequaln(second,third),'test:CompletedCampaignReran');
e=readtable(fullfile(root,'reports','csv','receiver_episodes.csv'),'TextType','string');
assert(height(e)==3&&numel(unique(e.NoiseSeed))==3&& ...
    isequal(e.SignalPresent,logical([0;1;1]))&&all(e.IndependentWaveformCount==1)&& ...
    ~any(e.StatisticallyQualified)&&~any(e.HypothesesAreIndependentTrials)&& ...
    all(e.CandidateCount==16)&&all(e.DecodeHypothesisCount==32));
s=readtable(fullfile(root,'reports','csv','qualification_status.csv'),'TextType','string');
assert(all(s.FinalFixedSampleLook)&&all(s.CIUpper>0.01));
badTag=tag+"_incomplete_contract"; bad=fullfile(output,badTag);
mkdir(bad); copyfile(fullfile(root,'meta'),fullfile(bad,'meta'));
mkdir(fullfile(bad,'episodes','episode_00000001')); reject(p,output,badTag);
badTag=tag+"_changed_input_contract"; bad=fullfile(output,badTag);
mkdir(bad); copyfile(fullfile(root,'meta'),fullfile(bad,'meta'));
inputs=dir(fullfile(bad,'meta','input_configs','*')); inputs=inputs(~[inputs.isdir]);
sixgr.util.writeTextFile(fullfile(inputs(1).folder,inputs(1).name),'TEST-ONLY CORRUPTED COPY');
reject(p,output,badTag);
fprintf('H4_INSTALLED_PDCCH_RESUME_PASS physical_episodes=3 qualified=0 folder=%s\n',root);
ok=true;
end
function reject(p,output,tag)
caught=false;
try, sixgr.link.runInstalledPDCCHReceiverCampaign(p,output,tag);
catch err
    assert(strcmp(err.identifier,'sixgr:pdcch:InstalledCampaignIntegrity'),err.getReport()); caught=true;
end
assert(caught,'test:CorruptCampaignResumed');
end
