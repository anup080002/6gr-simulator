function comparison = compare(configA, configB, varargin)
%COMPARE Execute paired A/B LLS curves with common random numbers.

ip = inputParser;
ip.addParameter("OutputRoot", "results/lls/comparisons", @(x) ischar(x) || isstring(x));
ip.addParameter("RunTag", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
[cfgA,~] = sixgr.lls.loadConfig(string(configA));
[cfgB,~] = sixgr.lls.loadConfig(string(configB));
if ~isequal(double(cfgA.simulation.snrDb(:)), double(cfgB.simulation.snrDb(:)))
    error("sixgr:lls:ComparisonSNRMismatch", ...
        "A/B comparison requires identical configured SNR points.");
end
keyA = string(sixgr.util.structGet(cfgA, "simulation.commonRandomKey", ""));
keyB = string(sixgr.util.structGet(cfgB, "simulation.commonRandomKey", ""));
if strlength(keyA) == 0 || keyA ~= keyB || cfgA.simulation.masterSeed ~= cfgB.simulation.masterSeed
    error("sixgr:lls:ComparisonRandomnessMismatch", ...
        "A/B comparison requires identical nonempty commonRandomKey and masterSeed.");
end
tag = string(ip.Results.RunTag);
if strlength(tag) == 0
    tag = string(datetime("now", "TimeZone", "UTC", "Format", "yyyyMMdd_HHmmss"));
end
root = string(ip.Results.OutputRoot);
root = string(java.io.File(char(root)).getCanonicalPath());
resultA = sixgr.lls.runLLS(configA, "OutputRoot", root, "RunTag", tag + "_A");
resultB = sixgr.lls.runLLS(configB, "OutputRoot", root, "RunTag", tag + "_B");
if resultA.Status ~= "complete_valid" || resultB.Status ~= "complete_valid"
    error("sixgr:lls:ComparisonInvalidConstituent", ...
        "A/B comparison requires two scientifically valid waveform runs.");
end
A = resultA.SummaryTable;
B = resultB.SummaryTable;
curveTable = table(A.SNRdB, A.BLER, B.BLER, A.NumTB, B.NumTB, ...
    'VariableNames', {'SNRdB','BLER_A','BLER_B','NumTB_A','NumTB_B'});
targets = double(sixgr.util.structGet(cfgA, "comparison.targetBLER", [0.1 0.01 0.001]));
rows = repmat(struct("TargetBLER",0,"RequiredSNR_A_dB",NaN,"RequiredSNR_B_dB",NaN, ...
    "Gain_dB",NaN,"Valid",false,"Status",""), numel(targets), 1);
for idx = 1:numel(targets)
    a = sixgr.lls.stats.interpolateRequiredSNR(A.SNRdB, A.BLER, targets(idx));
    b = sixgr.lls.stats.interpolateRequiredSNR(B.SNRdB, B.BLER, targets(idx));
    valid = a.Valid && b.Valid;
    rows(idx) = struct("TargetBLER",targets(idx), ...
        "RequiredSNR_A_dB",a.RequiredSNR_dB, ...
        "RequiredSNR_B_dB",b.RequiredSNR_dB, ...
        "Gain_dB",a.RequiredSNR_dB-b.RequiredSNR_dB, ...
        "Valid",valid, ...
        "Status",string(localComparisonStatus(valid)));
end
gainTable = struct2table(rows);
comparisonFolder = fullfile(char(root), "comparison_" + char(tag));
if exist(comparisonFolder,"dir") == 7
    error("sixgr:lls:OutputAlreadyExists", ...
        "Comparison output folder already exists: %s",comparisonFolder);
end
mkdir(comparisonFolder);
pairingTable = localPairingContract(resultA.TrialTable,resultB.TrialTable,A.SNRdB);
if ~all(pairingTable.CommonRandomNumbersMatch)
    error("sixgr:lls:ComparisonPairingViolation", ...
        "A/B trial streams differ for one or more matched operating points.");
end
writetable(curveTable, fullfile(comparisonFolder, "paired_bler_curves.csv"));
writetable(gainTable, fullfile(comparisonFolder, "required_snr_gain.csv"));
writetable(pairingTable,fullfile(comparisonFolder,"common_random_number_contract.csv"));
plotPath = sixgr.lls.plots.plotComparisonBLER(A,B,comparisonFolder);
provenance = struct( ...
    "SchemaVersion","sixgr.lls.comparison/v1", ...
    "ExecutionBackend","waveform_truth", ...
    "ApproximationMode","none", ...
    "ConfigA",string(configA),"ConfigB",string(configB), ...
    "ConfigSHA256A",resultA.ConfigSHA256, ...
    "ConfigSHA256B",resultB.ConfigSHA256, ...
    "ScientificSemanticSHA256A",resultA.ScientificSemanticSHA256, ...
    "ScientificSemanticSHA256B",resultB.ScientificSemanticSHA256, ...
    "CommonRandomKey",keyA,"MasterSeed",double(cfgA.simulation.masterSeed), ...
    "PairingValid",true,"InterpolationPolicy","interpolation_only_no_extrapolation", ...
    "CreatedUTC",string(datetime("now","TimeZone","UTC", ...
        "Format","yyyy-MM-dd'T'HH:mm:ss'Z'")));
localWriteJSON(fullfile(comparisonFolder,"comparison_provenance.json"),provenance);
manifest = localManifest(comparisonFolder);
writetable(manifest,fullfile(comparisonFolder,"artifact_manifest.csv"));
comparison = struct("Status","complete_valid","RunA",resultA,"RunB",resultB, ...
    "CurveTable",curveTable,"GainTable",gainTable,"PairingTable",pairingTable, ...
    "PlotPath",string(plotPath),"ArtifactManifest",manifest, ...
    "RunFolder",string(comparisonFolder));
end

function status = localComparisonStatus(valid)
if valid
    status = "valid_interpolation_no_extrapolation";
else
    status = "invalid_target_not_bracketed_by_both_simulated_curves";
end
end

function tableOut = localPairingContract(A,B,snrPoints)
rows = repmat(struct("SNRdB",0,"PairedTrials",0, ...
    "CommonRandomNumbersMatch",false,"Evidence",""),numel(snrPoints),1);
for idx = 1:numel(snrPoints)
    a = sortrows(A(A.SNRIndex == idx,:),"TrialIndex");
    b = sortrows(B(B.SNRIndex == idx,:),"TrialIndex");
    n = min(height(a),height(b));
    match = n > 0 && isequal(a.TrialIndex(1:n),b.TrialIndex(1:n)) ...
        && isequal(a.BitSeed(1:n),b.BitSeed(1:n)) ...
        && isequal(a.NoiseSeed(1:n),b.NoiseSeed(1:n)) ...
        && isequal(a.ChannelSeed(1:n),b.ChannelSeed(1:n));
    rows(idx) = struct("SNRdB",double(snrPoints(idx)), ...
        "PairedTrials",double(n),"CommonRandomNumbersMatch",logical(match), ...
        "Evidence","bit_noise_channel_seeds_match_for_every_paired_trial");
end
tableOut = struct2table(rows);
end

function localWriteJSON(path,value)
fid = fopen(path,"w","n","UTF-8");
if fid < 0
    error("sixgr:lls:ArtifactWriteFailed","Unable to write %s.",path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end

function manifest = localManifest(folder)
files = dir(fullfile(folder,"*"));
files = files(~[files.isdir]);
rows = repmat(struct("RelativePath","","Bytes",0,"SHA256","", ...
    "ArtifactType",""),numel(files),1);
for idx = 1:numel(files)
    path = fullfile(files(idx).folder,files(idx).name);
    [~,~,ext] = fileparts(path);
    rows(idx) = struct("RelativePath",string(files(idx).name), ...
        "Bytes",double(files(idx).bytes),"SHA256",localFileHash(path), ...
        "ArtifactType",upper(erase(string(ext),".")));
end
manifest = struct2table(rows);
end

function digest = localFileHash(path)
fid = fopen(path,"rb");
if fid < 0
    error("sixgr:lls:ArtifactReadFailed","Unable to read %s.",path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
digest = sixgr.util.sha256Hex(fread(fid,Inf,"*uint8"));
end
