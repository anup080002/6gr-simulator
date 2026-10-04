function ok=testRAN1AI1032StudyProvenance()
%TESTRAN1AI1032STUDYPROVENANCE Retain inherited inputs and resolved hash.
setup6GRSimToolkit('Verbose',false);
[study,provenance]=sixgr.studies.ran1ai1032.loadStudyConfig( ...
    'configs/tdoc/ai_10_3_2_modulation/c1_fixed.yaml');
assert(numel(provenance.SourceFiles)==2 && ...
    numel(provenance.SourceSHA256)==2 && ...
    strlength(string(provenance.WorktreeDiffSHA256))==64, ...
    'Inherited study provenance or working-tree diff hash is missing.');
folder=string(tempname);
assert(startsWith(folder,string(tempdir)), ...
    'test:UnsafeTemporaryPath','Provenance fixture must remain under tempdir.');
mkdir(folder); cleanup=onCleanup(@()localCleanup(folder)); %#ok<NASGU>
sixgr.studies.ran1ai1032.saveStudyInputProvenance(study,provenance,folder);
dir=fullfile(folder,'input_configs');
T=readtable(fullfile(dir,'source_files.csv'),'FileType','text', ...
    'Delimiter',',','ReadVariableNames',true,'TextType','string');
assert(height(T)==2 && all(isfile(fullfile(dir,T.RetainedCopy))) && ...
    all(string(T.SHA256)==string(provenance.SourceSHA256)), ...
    'Every inherited YAML must be retained with its original SHA-256.');
for k=1:height(T)
    assert(sixgr.csi.studyFileSHA256(fullfile(dir,T.RetainedCopy(k)))==T.SHA256(k));
end
resolved=jsondecode(fileread(fullfile(dir,'resolved_study.json')));
record=jsondecode(fileread(fullfile(dir,'provenance.json')));
assert(string(resolved.lls.execution.representation_id)=="C1" && ...
    string(record.ResolvedConfigSHA256)==provenance.ConfigSHA256 && ...
    string(record.WorktreeDiffSHA256)==provenance.WorktreeDiffSHA256);
ok=true;
fprintf('RAN1_AI1032_STUDY_PROVENANCE_PASS sources=%d\n',height(T));
end

function localCleanup(folder)
if isfolder(folder)
    assert(startsWith(string(folder),string(tempdir)), ...
        'test:UnsafeTemporaryPath','Refusing to delete outside tempdir.');
    rmdir(folder,'s');
end
end
