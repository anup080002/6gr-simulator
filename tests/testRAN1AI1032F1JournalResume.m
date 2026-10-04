function ok=testRAN1AI1032F1JournalResume()
%TESTRAN1AI1032F1JOURNALRESUME Exact physical-row recovery across invocations.
setup6GRSimToolkit('Verbose',false);
root=string(tempname);
assert(startsWith(root,string(tempdir)), ...
    'test:UnsafeTemporaryPath','The temporary campaign must remain under tempdir.');
mkdir(root);
clean=onCleanup(@()localCleanup(root)); %#ok<NASGU>
source=fileread('configs/tdoc/ai_10_3_2_modulation/study.yaml');
replacements={ ...
    '    transport_blocks_per_invocation: 32','    transport_blocks_per_invocation: 1'; ...
    '    channel_profiles: [AWGN, CDL-A, CDL-B, CDL-C]','    channel_profiles: [AWGN]'; ...
    '    entry_ids: [B27, H0, H1, H2, H3]','    entry_ids: [B27]'; ...
    '    ranks: [1, 2, 4]',sprintf('    ranks: [1]\n    antenna_case_ids: [simo_1x4_r1]'); ...
    '    rf_branch: pn7_ptrs_compensated','    rf_branch: pn_off_ptrs_reference'};
for k=1:size(replacements,1)
    assert(contains(source,replacements{k,1}), ...
        'test:StudyFixtureChanged','The study YAML fixture changed.');
    source=strrep(source,replacements{k,1},char(replacements{k,2}));
end
studyPath=fullfile(root,'study.yaml');
fid=fopen(studyPath,'wt'); assert(fid>=0,'test:WriteFixture','Cannot write study fixture.');
closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',source); clear closeFile;
outRoot=fullfile(root,'results'); tag='journal_resume';
first=sixgr.studies.ran1ai1032.runF1CalibrationCampaign( ...
    string(studyPath),string(outRoot),string(tag));
assert(first.TransportBlocksThisInvocation==1 && ~first.AllPointsComplete);
caseDir=fullfile(first.RunFolder,'f1_awgn_ds0_simo_1x4_r1_r1_b27');
checkpoint=fullfile(caseDir,'case_checkpoint.mat');
saved=load(checkpoint,'state');
assert(saved.state.TrialCount==1 && isempty(saved.state.Trials) && ...
    width(saved.state.Trials)>0, ...
    'F1 checkpoints must preserve only the typed schema and durable row count.');
second=sixgr.studies.ran1ai1032.runF1CalibrationCampaign( ...
    string(studyPath),string(outRoot),string(tag));
assert(second.TransportBlocksThisInvocation==1);
rows=readtable(fullfile(caseDir,'snr_minus_10p0000_trials.csv'));
assert(height(rows)==2 && isequal(rows.TrialOrdinal,[1;2]) && ...
    numel(unique(rows.Seed))==2 && all(string(rows.SourceClassification)=="executed_phy_truth"), ...
    'Resume must append one new physical trial, with no duplicate or synthetic row.');
% Model a crash after the second CSV append but before its checkpoint.
saved=load(checkpoint,'state'); saved.state.TrialCount=1;
state=saved.state; save(checkpoint,'state','-v7.3');
third=sixgr.studies.ran1ai1032.runF1CalibrationCampaign( ...
    string(studyPath),string(outRoot),string(tag));
assert(third.TransportBlocksThisInvocation==1);
rows=readtable(fullfile(caseDir,'snr_minus_10p0000_trials.csv'));
saved=load(checkpoint,'state');
assert(height(rows)==3 && isequal(rows.TrialOrdinal,[1;2;3]) && ...
    saved.state.TrialCount==3 && isempty(saved.state.Trials), ...
    'A valid journal row ahead of its compact checkpoint must be recovered exactly.');
ok=true;
fprintf('RAN1_AI1032_F1_JOURNAL_RESUME_PASS physical_trials=%d\n',height(rows));
end

function localCleanup(root)
if isfolder(root)
    assert(startsWith(string(root),string(tempdir)), ...
        'test:UnsafeTemporaryPath','Refusing to delete outside tempdir.');
    rmdir(root,'s');
end
end
