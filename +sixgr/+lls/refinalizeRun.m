function result = refinalizeRun(runFolder)
%REFINALIZERUN Recompute derived gates from immutable waveform evidence.
% This function does not execute or alter any transport-block trial. It
% validates the persisted config/trial/summary truth, recomputes derived
% required-SNR and validity artifacts, then atomically refreshes provenance
% and the root artifact manifest.

arguments
    runFolder (1,1) string
end
runFolder = string(char(java.io.File(char(runFolder)).getCanonicalPath()));
requiredFiles = ["resolved_config.json","bler_vs_snr.csv", ...
    "transport_block_trials.csv","truth_contract.csv","run_provenance.json"];
for index = 1:numel(requiredFiles)
    if exist(fullfile(runFolder,requiredFiles(index)),"file") ~= 2
        error("sixgr:lls:MissingRunEvidence", ...
            "Cannot re-finalize because %s is missing.",requiredFiles(index));
    end
end

cfg = jsondecode(fileread(fullfile(runFolder,"resolved_config.json")));
cfg = sixgr.lls.validateConfig(cfg,"ConfigPath",fullfile(runFolder,"resolved_config.json"));
summary = readtable(fullfile(runFolder,"bler_vs_snr.csv"),"TextType","string");
trials = readtable(fullfile(runFolder,"transport_block_trials.csv"),"TextType","string");
contract = readtable(fullfile(runFolder,"truth_contract.csv"),"TextType","string");
required = sixgr.lls.requiredSNRTable(cfg,summary);
[validity,valid] = sixgr.lls.validateResults(cfg,summary,trials,contract,required);

localAtomicWriteTable(required,fullfile(runFolder,"required_snr_at_target_bler.csv"));
localAtomicWriteTable(validity,fullfile(runFolder,"result_validity.csv"));
provenancePath = fullfile(runFolder,"run_provenance.json");
provenance = jsondecode(fileread(provenancePath));
provenance.ResultValidity = char(localStatus(valid));
provenance.FinalizerSchemaVersion = "sixgr.lls.refinalize/v1";
provenance.FinalizedUTC = char(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss'Z'"));
provenance.RequiredSNREstimationPolicy = ...
    "empirical_crossing_or_zero_error_wilson_confidence_bracket";
provenance.RequiredSNRSHA256 = localFileHash( ...
    fullfile(runFolder,"required_snr_at_target_bler.csv"));
localAtomicWriteJSON(provenance,provenancePath);
manifest = localArtifactManifest(runFolder);
localAtomicWriteTable(manifest,fullfile(runFolder,"artifact_manifest.csv"));

result = struct("Status",localStatus(valid),"RunFolder",runFolder, ...
    "RequiredSNRTable",required,"ValidityTable",validity, ...
    "ArtifactManifest",manifest,"TransportBlockRows",height(trials));
end

function manifest = localArtifactManifest(folder)
files = dir(fullfile(folder,"*"));
files = files(~[files.isdir]);
files = files(~strcmpi({files.name},"artifact_manifest.csv"));
rows = repmat(struct("RelativePath","","Bytes",0,"SHA256","", ...
    "ArtifactType",""),numel(files),1);
for index = 1:numel(files)
    path = fullfile(files(index).folder,files(index).name);
    [~,~,ext] = fileparts(path);
    rows(index) = struct("RelativePath",string(files(index).name), ...
        "Bytes",double(files(index).bytes),"SHA256",localFileHash(path), ...
        "ArtifactType",upper(erase(string(ext),".")));
end
manifest = struct2table(rows);
end

function localAtomicWriteTable(value,path)
folder = fileparts(path);
temporary = string(tempname(folder)) + ".csv";
cleanup = onCleanup(@()localDeleteIfPresent(temporary)); %#ok<NASGU>
writetable(value,temporary);
[ok,message] = movefile(temporary,path,"f");
if ~ok
    error("sixgr:lls:ArtifactWriteFailed", ...
        "Unable to atomically publish %s: %s",path,message);
end
end

function localAtomicWriteJSON(value,path)
folder = fileparts(path);
temporary = string(tempname(folder)) + ".json";
cleanup = onCleanup(@()localDeleteIfPresent(temporary)); %#ok<NASGU>
fid = fopen(temporary,"w","n","UTF-8");
if fid < 0
    error("sixgr:lls:ArtifactWriteFailed","Unable to open %s.",temporary);
end
fileCleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
clear fileCleanup;
[ok,message] = movefile(temporary,path,"f");
if ~ok
    error("sixgr:lls:ArtifactWriteFailed", ...
        "Unable to atomically publish %s: %s",path,message);
end
end

function digest = localFileHash(path)
fid = fopen(path,"rb");
if fid < 0
    error("sixgr:lls:ArtifactReadFailed","Unable to read %s.",path);
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
digest = sixgr.util.sha256Hex(fread(fid,Inf,"*uint8"));
end

function localDeleteIfPresent(path)
if exist(path,"file") == 2
    delete(path);
end
end

function value = localStatus(valid)
if valid
    value = "complete_valid";
else
    value = "complete_invalid";
end
end
