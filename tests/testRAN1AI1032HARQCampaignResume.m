function ok=testRAN1AI1032HARQCampaignResume()
% Two actual full-band TBs exercise collection, held-out seeds and resume.
% Small episode counts are a contract check, never statistical acceptance.
study=sixgr.studies.ran1ai1032.loadStudyConfig();
study.lls.execution.channel_profiles={'AWGN'};
study.lls.execution.entry_ids={'B27'}; study.lls.execution.ranks=1;
study.lls.execution.antenna_case_ids={'simo_1x4_r1'};
study.lls.execution.rf_branch='ideal_debug';
study.harq.calibration.snr_histories_db=[40 40 40 40];
study.harq.calibration.fit_episodes_per_history=1;
study.harq.calibration.validation_episodes_per_history=1;
study.harq.calibration.episodes_per_invocation=1;
folder=string(tempname(fullfile(pwd,'logs'))); mkdir(folder);
path=fullfile(folder,'contract_study.json'); sixgr.util.jsonWrite(path,study);
a=sixgr.studies.ran1ai1032.runHARQCalibrationCampaign(path,folder,'resume_fixture');
assert(a.EpisodesCompleted==1 && ~a.AllEpisodesComplete && ~a.PrimaryStudyAccepted);
b=sixgr.studies.ran1ai1032.runHARQCalibrationCampaign(path,folder,'resume_fixture');
assert(b.EpisodesCompleted==2 && b.AllEpisodesComplete && ~b.PrimaryStudyAccepted);
files=dir(fullfile(b.RunFolder,'**','fit_attempts.csv')); assert(isscalar(files));
fit=readtable(fullfile(files.folder,files.name),'TextType','string');
val=readtable(fullfile(files.folder,'validation_attempts.csv'),'TextType','string');
assert(height(fit)==1 && height(val)==1 && fit.CRCPass && val.CRCPass);
assert(fit.Seed~=val.Seed && fit.TrialID~=val.TrialID);
configs=load(fullfile(files.folder,'fit_episode_1_resolved.mat'),'resolvedConfigurations');
assert(numel(configs.resolvedConfigurations)==height(fit));
digest=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(configs.resolvedConfigurations{1})),'UTF-8'))));
assert(digest==fit.ResolvedConfigSHA256);
study.harq.calibration.episodes_per_invocation=2; sixgr.util.jsonWrite(path,study);
c=sixgr.studies.ran1ai1032.runHARQCalibrationCampaign(path,folder,'resume_fixture');
assert(c.AllEpisodesComplete && c.EpisodesThisInvocation==0 && c.CampaignIdentity==b.CampaignIdentity);
saved=load(fullfile(c.RunFolder,'identity.mat'),'sourceText'); assert(~isempty(saved.sourceText));
study.harq.calibration.seed_base=study.harq.calibration.seed_base+1; sixgr.util.jsonWrite(path,study);
try
    sixgr.studies.ran1ai1032.runHARQCalibrationCampaign(path,folder,'resume_fixture');
    error('test:ExpectedError','Scientific changes must not resume old populations.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:ran1ai1032:HARQResumeIdentity'),'%s',ME.message);
end
fprintf('F1_HARQ_RESUME_PASS fullband_TBs=2 statistical_qualification=0 folder=%s\n',folder);
ok=true;
end
