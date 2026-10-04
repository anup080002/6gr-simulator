function saveStudyInputProvenance(study,provenance,folder)
%SAVESTUDYINPUTPROVENANCE Retain every inherited YAML and resolved study.
arguments
    study struct
    provenance struct
    folder (1,1) string
end
sources=string(provenance.SourceFiles(:)); hashes=string(provenance.SourceSHA256(:));
assert(numel(sources)==numel(hashes) && ~isempty(sources), ...
    'sixgr:ran1ai1032:StudyProvenance', ...
    'Every resolved study source must have its SHA-256 identity.');
destination=fullfile(folder,'input_configs');
if ~isfolder(destination), mkdir(destination); end
retained=strings(size(sources));
for k=1:numel(sources)
    [~,base,ext]=fileparts(sources(k));
    retained(k)=compose('%02d_',k)+string(base)+string(ext);
    target=fullfile(destination,retained(k));
    [ok,msg]=copyfile(sources(k),target);
    assert(ok,'sixgr:ran1ai1032:StudyProvenance','%s',msg);
    assert(sixgr.csi.studyFileSHA256(target)==hashes(k), ...
        'sixgr:ran1ai1032:StudyProvenance', ...
        'The retained study YAML differs from its loaded source.');
end
manifest=table(sources,hashes,retained, ...
    'VariableNames',{'SourceFile','SHA256','RetainedCopy'});
localWriteTable(fullfile(destination,'source_files.csv'),manifest);
resolved=jsonencode(study);
localWriteText(fullfile(destination,'resolved_study.json'),resolved);
record=struct('Schema','sixgr.ran1ai1032.study_provenance/v1', ...
    'ResolvedConfigSHA256',string(provenance.ConfigSHA256), ...
    'GitCommit',string(provenance.GitCommit), ...
    'WorktreeDiffSHA256',string(provenance.WorktreeDiffSHA256), ...
    'ResolvedStudyJSONSHA256',string(sixgr.util.sha256Hex( ...
        uint8(unicode2native(resolved,'UTF-8')))));
localWriteText(fullfile(destination,'provenance.json'),jsonencode(record));
end

function localWriteTable(path,T)
temporary=path+'.partial.csv'; writetable(T,temporary);
[ok,msg]=movefile(temporary,path,'f');
assert(ok,'sixgr:ran1ai1032:StudyProvenance','%s',msg);
end

function localWriteText(path,value)
temporary=path+'.partial'; fid=fopen(temporary,'wt');
assert(fid>=0,'sixgr:ran1ai1032:StudyProvenance','Cannot write %s.',temporary);
closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',value); clear closeFile;
[ok,msg]=movefile(temporary,path,'f');
assert(ok,'sixgr:ran1ai1032:StudyProvenance','%s',msg);
end
