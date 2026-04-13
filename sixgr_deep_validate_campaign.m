function out = sixgr_deep_validate_campaign(runFolder, varargin)
%SIXGR_DEEP_VALIDATE_CAMPAIGN Deep post-run validation for full 3GPP campaign.
%
% This utility scans all campaign artifacts and writes a detailed validation
% package under:
%   <runFolder>/deep_validation/
%
% Generated outputs:
%   - deep_artifact_inventory.csv
%   - deep_csv_readcheck.csv
%   - deep_mat_readcheck.csv
%   - deep_figure_readcheck.csv
%   - deep_artifact_checklist_revalidated.csv
%   - deep_e2e_stage_totals.csv
%   - deep_e2e_stage_edges.csv
%   - deep_e2e_component_checks_enriched.csv
%   - deep_control_path_summary.csv
%   - deep_data_path_summary.csv
%   - deep_kpi_highlights.csv
%   - deep_validation_summary.mat
%   - deep_validation_report.md

ip = inputParser;
ip.addRequired("runFolder", @(x)ischar(x)||isstring(x));
ip.addParameter("OutputFolder", "", @(x)ischar(x)||isstring(x));
ip.addParameter("Verbose", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(runFolder, varargin{:});
opt = ip.Results;

runFolder = char(string(opt.runFolder));
if ~isfolder(runFolder)
    error("sixgr:deepValidate:RunFolderNotFound", "Run folder not found: %s", runFolder);
end
runFolder = localCanonicalPath(runFolder);
layout = sixgr.report.resultLayout(runFolder);

outFolder = char(string(opt.OutputFolder));
if strlength(string(outFolder)) == 0
    outFolder = fullfile(runFolder, "deep_validation");
end
localEnsureDir(outFolder);
verbose = logical(opt.Verbose);

if verbose
    fprintf("[deep-validate] Run folder: %s\n", runFolder);
    fprintf("[deep-validate] Output folder: %s\n", outFolder);
end

% -------------------------------------------------------------------------
% 1) Inventory and readability checks across all artifacts
% -------------------------------------------------------------------------
inv = localCollectArtifacts(runFolder);
invCSV = fullfile(outFolder, "deep_artifact_inventory.csv");
writetable(inv.Table, invCSV);

csvCheck = localCheckCSVArtifacts(runFolder, inv.Table);
csvCheckCSV = fullfile(outFolder, "deep_csv_readcheck.csv");
writetable(csvCheck.Table, csvCheckCSV);

matCheck = localCheckMATArtifacts(runFolder, inv.Table);
matCheckCSV = fullfile(outFolder, "deep_mat_readcheck.csv");
writetable(matCheck.Table, matCheckCSV);

figCheck = localCheckFigureArtifacts(runFolder, inv.Table);
figCheckCSV = fullfile(outFolder, "deep_figure_readcheck.csv");
writetable(figCheck.Table, figCheckCSV);

% -------------------------------------------------------------------------
% 2) Key table loads
% -------------------------------------------------------------------------
T_slot = localLoadCSVAbs(fullfile(layout.PacketFlowCSVDir, "probe_e2e_slot_metrics.csv"));
T_io = localLoadCSVAbs(fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_io.csv"));
T_chk = localLoadCSVAbs(fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_checks.csv"));
T_e2e = localLoadCSVAbs(fullfile(layout.PacketFlowCSVDir, "probe_e2e_summary.csv"));
T_ai = localLoadCSVAbs(fullfile(layout.PacketFlowCSVDir, "probe_e2e_ai_metrics.csv"));
T_sync = localLoadCSVAbs(fullfile(layout.ControlCSVDir, "probe_sync_control.csv"));
T_harq = localLoadCSVAbs(fullfile(layout.HARQCSVDir, "probe_harq_summary.csv"));
T_lls = localLoadCSVAbs(fullfile(layout.AirInterfaceCSVDir, "lls_kpi_summary.csv"));
T_snr = localLoadCSVAbs(fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv"));
T_sys = localLoadCSVAbs(fullfile(layout.SystemCSVDir, "system_kpis.csv"));
T_mmtc = localLoadCSVAbs(fullfile(layout.MMTCCSVDir, "probe_mmtc_kpis.csv"));
T_v2x = localLoadCSVAbs(fullfile(layout.V2XCSVDir, "probe_v2x_sidelink.csv"));
T_ntn = localLoadCSVAbs(fullfile(layout.NTNCSVDir, "probe_ntn_delay_doppler.csv"));
T_intf = localLoadCSVAbs(fullfile(layout.InterferenceCSVDir, "probe_interference_sir_bler.csv"));
T_num = localLoadCSVAbs(fullfile(layout.NumerologyCSVDir, "probe_numerology.csv"));
T_beam = localLoadCSVAbs(fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv"));
T_audit = localLoadCSVAbs(layout.CategoryAuditCSV);
T_art = localLoadCSVAbs(layout.ArtifactChecklistCSV);

% -------------------------------------------------------------------------
% 3) Revalidate artifact checklist after all files are fully written
% -------------------------------------------------------------------------
artRe = localRevalidateArtifactChecklist(runFolder, T_art);
artReCSV = fullfile(outFolder, "deep_artifact_checklist_revalidated.csv");
writetable(artRe.Table, artReCSV);

% -------------------------------------------------------------------------
% 4) Deep E2E control/data-flow validation
% -------------------------------------------------------------------------
flow = localAnalyzeE2EFlow(T_slot, T_io, T_chk, T_e2e, T_sync);
stageTotalsCSV = fullfile(outFolder, "deep_e2e_stage_totals.csv");
stageEdgesCSV = fullfile(outFolder, "deep_e2e_stage_edges.csv");
compChecksCSV = fullfile(outFolder, "deep_e2e_component_checks_enriched.csv");
controlCSV = fullfile(outFolder, "deep_control_path_summary.csv");
dataCSV = fullfile(outFolder, "deep_data_path_summary.csv");
writetable(flow.StageTotals, stageTotalsCSV);
writetable(flow.StageEdges, stageEdgesCSV);
writetable(flow.ComponentChecks, compChecksCSV);
writetable(flow.ControlSummary, controlCSV);
writetable(flow.DataSummary, dataCSV);

% -------------------------------------------------------------------------
% 5) Cross-probe KPI highlight extraction
% -------------------------------------------------------------------------
kpi = localExtractHighlights(T_lls, T_snr, T_sys, T_harq, T_mmtc, T_v2x, T_ntn, T_intf, T_num, T_beam, T_ai, T_audit, T_e2e);
kpiCSV = fullfile(outFolder, "deep_kpi_highlights.csv");
writetable(kpi.Table, kpiCSV);

% -------------------------------------------------------------------------
% 6) Compose markdown report
% -------------------------------------------------------------------------
mdFile = fullfile(outFolder, "deep_validation_report.md");
controlStatus = localSummaryStatus(flow.ControlSummary);
dataStatus = localSummaryStatus(flow.DataSummary);
overallOk = (csvCheck.ReadFailCount == 0) && (matCheck.ReadFailCount == 0) && (figCheck.ReadFailCount == 0) && ...
    (double(artRe.MissingRequired) <= 0) && (controlStatus ~= "FAIL") && (dataStatus ~= "FAIL");
localWriteDeepMarkdown(mdFile, runFolder, outFolder, inv, csvCheck, matCheck, figCheck, artRe, flow, kpi, overallOk, controlStatus, dataStatus);

% MAT snapshot of all analysis objects.
matFile = fullfile(outFolder, "deep_validation_summary.mat");
out = struct();
out.RunFolder = string(runFolder);
out.OutputFolder = string(outFolder);
out.Inventory = inv;
out.CSVCheck = csvCheck;
out.MATCheck = matCheck;
out.FigureCheck = figCheck;
out.ArtifactRevalidated = artRe;
out.Flow = flow;
out.KPI = kpi;
out.OverallOk = logical(overallOk);
if out.OverallOk
    out.OverallStatus = "PASS";
else
    out.OverallStatus = "FAIL";
end
out.ControlStatus = controlStatus;
out.DataStatus = dataStatus;
out.GeneratedFiles = string({ ...
    invCSV, csvCheckCSV, matCheckCSV, figCheckCSV, artReCSV, ...
    stageTotalsCSV, stageEdgesCSV, compChecksCSV, controlCSV, dataCSV, ...
    kpiCSV, mdFile, matFile});
save(matFile, "-struct", "out");

if verbose
    fprintf("[deep-validate] Completed. Report: %s\n", mdFile);
end
end

function localEnsureDir(p)
if exist(p, "dir") ~= 7
    mkdir(p);
end
end

function p = localCanonicalPath(p0)
cur = pwd;
c = onCleanup(@() cd(cur)); %#ok<NASGU>
cd(p0);
p = pwd;
end

function out = localCollectArtifacts(runFolder)
d = dir(fullfile(runFolder, "**", "*"));
d = d(~[d.isdir]);
n = numel(d);

rel = strings(n,1);
ext = strings(n,1);
kind = strings(n,1);
bytes = zeros(n,1);
mtime = strings(n,1);
isTop = false(n,1);

prefix = string(runFolder);
if ~endsWith(prefix, filesep)
    prefix = prefix + filesep;
end

for i = 1:n
    fullPath = string(fullfile(d(i).folder, d(i).name));
    if startsWith(fullPath, prefix, "IgnoreCase", true)
        rp = extractAfter(fullPath, strlength(prefix));
    else
        rp = fullPath;
    end
    rp = replace(rp, "\", "/");
    [~, ~, e] = fileparts(d(i).name);
    e = lower(string(e));
    rel(i) = rp;
    ext(i) = e;
    kind(i) = localKindFromExt(e);
    bytes(i) = double(d(i).bytes);
    mtime(i) = string(datetime(d(i).datenum, "ConvertFrom", "datenum", "Format", "yyyy-MM-dd HH:mm:ss"));
    isTop(i) = ~contains(rp, "/");
end

T = table(rel, ext, kind, bytes, mtime, isTop, ...
    'VariableNames', {'RelativePath','Extension','Kind','SizeBytes','ModifiedTime','IsTopLevel'});

out = struct();
out.Table = sortrows(T, "RelativePath");
out.TotalFiles = height(T);
out.CSVCount = sum(out.Table.Extension == ".csv");
out.MATCount = sum(out.Table.Extension == ".mat");
out.FigureCount = sum(ismember(out.Table.Extension, [".png",".jpg",".jpeg",".pdf",".fig"]));
end

function k = localKindFromExt(ext)
switch char(ext)
    case ".csv"
        k = "csv";
    case ".mat"
        k = "mat";
    case {".png",".jpg",".jpeg",".pdf",".fig"}
        k = "figure";
    case ".md"
        k = "markdown";
    case ".log"
        k = "log";
    case ".json"
        k = "json";
    case ".m"
        k = "script";
    otherwise
        k = "other";
end
end

function out = localCheckCSVArtifacts(runFolder, Tinv)
mask = Tinv.Extension == ".csv";
files = Tinv.RelativePath(mask);
n = numel(files);

fRel = strings(n,1);
ok = false(n,1);
nRows = NaN(n,1);
nCols = NaN(n,1);
numVals = NaN(n,1);
nonFinite = NaN(n,1);
varNames = strings(n,1);
notes = strings(n,1);

for i = 1:n
    fRel(i) = files(i);
    f = fullfile(runFolder, char(replace(files(i), "/", filesep)));
    try
        T = readtable(f, "VariableNamingRule", "preserve");
        ok(i) = true;
        nRows(i) = double(height(T));
        nCols(i) = double(width(T));
        [numVals(i), nonFinite(i)] = localNumericCoverage(T);
        varNames(i) = localJoinNames(string(T.Properties.VariableNames), 240);
        notes(i) = "";
    catch ME
        ok(i) = false;
        notes(i) = string(ME.message);
        varNames(i) = "";
    end
end

Tout = table(fRel, ok, nRows, nCols, numVals, nonFinite, varNames, notes, ...
    'VariableNames', {'RelativePath','ReadOK','Rows','Cols','NumericValues','NonFiniteValues','Columns','Notes'});

out = struct();
out.Table = sortrows(Tout, "RelativePath");
out.Total = n;
out.ReadOKCount = sum(ok);
out.ReadFailCount = n - sum(ok);
end

function out = localCheckMATArtifacts(runFolder, Tinv)
mask = Tinv.Extension == ".mat";
files = Tinv.RelativePath(mask);
n = numel(files);

fRel = strings(n,1);
ok = false(n,1);
varCount = NaN(n,1);
totalBytes = NaN(n,1);
vars = strings(n,1);
notes = strings(n,1);

for i = 1:n
    fRel(i) = files(i);
    f = fullfile(runFolder, char(replace(files(i), "/", filesep)));
    try
        info = whos("-file", f);
        ok(i) = true;
        varCount(i) = numel(info);
        if isempty(info)
            totalBytes(i) = 0;
            vars(i) = "";
        else
            totalBytes(i) = sum([info.bytes]);
            vars(i) = localJoinNames(string({info.name}), 240);
        end
        notes(i) = "";
    catch ME
        ok(i) = false;
        notes(i) = string(ME.message);
    end
end

Tout = table(fRel, ok, varCount, totalBytes, vars, notes, ...
    'VariableNames', {'RelativePath','ReadOK','VariableCount','VariableBytes','VariableNamesList','Notes'});
out = struct();
out.Table = sortrows(Tout, "RelativePath");
out.Total = n;
out.ReadOKCount = sum(ok);
out.ReadFailCount = n - sum(ok);
end

function out = localCheckFigureArtifacts(runFolder, Tinv)
mask = ismember(Tinv.Extension, [".png",".jpg",".jpeg",".pdf",".fig"]);
files = Tinv.RelativePath(mask);
n = numel(files);

fRel = strings(n,1);
ok = false(n,1);
w = NaN(n,1);
h = NaN(n,1);
sizeKB = NaN(n,1);
notes = strings(n,1);

for i = 1:n
    fRel(i) = files(i);
    f = fullfile(runFolder, char(replace(files(i), "/", filesep)));
    if exist(f, "file") ~= 2
        notes(i) = "missing";
        continue;
    end
    dd = dir(f);
    if ~isempty(dd)
        sizeKB(i) = double(dd(1).bytes) / 1024;
    end
    [~, ~, e] = fileparts(f);
    e = lower(string(e));
    try
        switch char(e)
            case {".png",".jpg",".jpeg"}
                info = imfinfo(f);
                w(i) = double(info.Width);
                h(i) = double(info.Height);
                ok(i) = true;
            case {".pdf",".fig"}
                ok(i) = dd(1).bytes > 0;
            otherwise
                ok(i) = dd(1).bytes > 0;
        end
        if ok(i)
            notes(i) = "";
        else
            notes(i) = "zero-size or unreadable";
        end
    catch ME
        ok(i) = false;
        notes(i) = string(ME.message);
    end
end

Tout = table(fRel, ok, w, h, sizeKB, notes, ...
    'VariableNames', {'RelativePath','ReadOK','Width','Height','SizeKB','Notes'});
out = struct();
out.Table = sortrows(Tout, "RelativePath");
out.Total = n;
out.ReadOKCount = sum(ok);
out.ReadFailCount = n - sum(ok);
end

function T = localLoadCSV(runFolder, relPath)
f = fullfile(runFolder, char(replace(string(relPath), "/", filesep)));
T = localLoadCSVAbs(f);
end

function T = localLoadCSVAbs(f)
if exist(f, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(f, "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function out = localRevalidateArtifactChecklist(runFolder, Tart)
if isempty(Tart)
    Tout = table();
    out = struct("Table", Tout, "RequiredCoverage_pct", NaN, "MissingRequired", NaN, "DisagreementCount", NaN);
    return;
end

T = Tart;
if ~ismember("Pattern", string(T.Properties.VariableNames))
    Tout = table();
    out = struct("Table", Tout, "RequiredCoverage_pct", NaN, "MissingRequired", NaN, "DisagreementCount", NaN);
    return;
end

n = height(T);
existsNow = false(n,1);
foundNow = zeros(n,1);
statusNow = strings(n,1);

req = localColumnOrDefault(T, "Required", true(n,1));
oldExists = localColumnOrDefault(T, "Exists", false(n,1));
req = localToDouble(req) > 0;
oldExists = localToDouble(oldExists) > 0;

for i = 1:n
    pat = char(string(T.Pattern(i)));
    pat = strrep(pat, "/", filesep);
    q = fullfile(runFolder, pat);
    d = dir(q);
    d = d(~[d.isdir]);
    foundNow(i) = numel(d);
    existsNow(i) = foundNow(i) > 0;
    if existsNow(i)
        statusNow(i) = "ok";
    elseif req(i)
        statusNow(i) = "missing_required";
    else
        statusNow(i) = "missing_optional";
    end
end

Tout = T;
Tout.Exists_Revalidated = existsNow;
Tout.FoundCount_Revalidated = foundNow;
Tout.Status_Revalidated = statusNow;
Tout.WasMismatched = oldExists ~= existsNow;

reqMask = logical(req);
if any(reqMask)
    covPct = 100 * mean(double(existsNow(reqMask)));
else
    covPct = 100;
end
missingReq = sum(reqMask & ~existsNow);
mismatchN = sum(Tout.WasMismatched);

out = struct();
out.Table = Tout;
out.RequiredCoverage_pct = covPct;
out.MissingRequired = double(missingReq);
out.DisagreementCount = double(mismatchN);
end

function v = localColumnOrDefault(T, name, defaultV)
if ismember(name, string(T.Properties.VariableNames))
    v = T.(name);
else
    v = defaultV;
end
end

function out = localAnalyzeE2EFlow(T_slot, T_io, T_chk, T_e2e, T_sync)
[stageTotals, stageEdges] = localBuildStageTables(T_io);
compChecks = localBuildComponentChecks(T_chk);
ctrl = localBuildControlSummary(T_sync, T_e2e);
data = localBuildDataSummary(T_slot, T_e2e, stageTotals, compChecks);

out = struct();
out.StageTotals = stageTotals;
out.StageEdges = stageEdges;
out.ComponentChecks = compChecks;
out.ControlSummary = ctrl;
out.DataSummary = data;
end

function [stageTotals, stageEdges] = localBuildStageTables(T_io)
if isempty(T_io)
    stageTotals = table();
    stageEdges = table();
    return;
end

dlCols = { ...
    "DL_AppIn_Bytes", "DL_SDAP_TxOut_Bytes", "DL_PDCP_TxOut_Bytes", ...
    "DL_RLC_TxOut_Bytes", "DL_MAC_TBOut_Bytes", "DL_Air_RxIn_Bytes", ...
    "DL_MAC_DisasmOut_Bytes", "DL_RLC_RxOut_Bytes", "DL_PDCP_RxOut_Bytes", ...
    "DL_AppOut_Bytes"};
ulCols = { ...
    "UL_AppIn_Bytes", "UL_SDAP_TxOut_Bytes", "UL_PDCP_TxOut_Bytes", ...
    "UL_RLC_TxOut_Bytes", "UL_MAC_TBOut_Bytes", "UL_Air_RxIn_Bytes", ...
    "UL_MAC_DisasmOut_Bytes", "UL_RLC_RxOut_Bytes", "UL_PDCP_RxOut_Bytes", ...
    "UL_AppOut_Bytes"};
stageNames = { ...
    "AppIn","SDAP_TxOut","PDCP_TxOut","RLC_TxOut","MAC_TBOut", ...
    "Air_RxIn","MAC_DisasmOut","RLC_RxOut","PDCP_RxOut","AppOut"};

dlBytes = localSumColumns(T_io, dlCols);
ulBytes = localSumColumns(T_io, ulCols);

nS = numel(stageNames);
Direction = [repmat("DL", nS, 1); repmat("UL", nS, 1)];
Stage = [string(stageNames(:)); string(stageNames(:))];
Bytes = [dlBytes(:); ulBytes(:)];
ActiveFlow = Bytes > 0;

stageTotals = table(Direction, Stage, Bytes, ActiveFlow);

rows = repmat(struct( ...
    "Direction", "", ...
    "FromStage", "", ...
    "ToStage", "", ...
    "FromBytes", 0, ...
    "ToBytes", 0, ...
    "TransferRatio", NaN, ...
    "FlowPresent", false), 2*(nS-1), 1);
r = 0;
for d = 1:2
    if d == 1
        dirName = "DL";
        b = dlBytes;
    else
        dirName = "UL";
        b = ulBytes;
    end
    for i = 1:(nS-1)
        r = r + 1;
        fromB = b(i);
        toB = b(i+1);
        rows(r).Direction = dirName;
        rows(r).FromStage = string(stageNames{i});
        rows(r).ToStage = string(stageNames{i+1});
        rows(r).FromBytes = fromB;
        rows(r).ToBytes = toB;
        rows(r).TransferRatio = toB / max(fromB, 1);
        rows(r).FlowPresent = (fromB > 0) && (toB > 0);
    end
end
stageEdges = struct2table(rows);
end

function v = localSumColumns(T, cols)
n = numel(cols);
v = zeros(n,1);
for i = 1:n
    c = string(cols{i});
    if ismember(c, string(T.Properties.VariableNames))
        x = T.(c);
        if isnumeric(x) || islogical(x)
            v(i) = sum(double(x), "omitnan");
        else
            v(i) = 0;
        end
    else
        v(i) = 0;
    end
end
end

function comp = localBuildComponentChecks(T_chk)
if isempty(T_chk)
    comp = table();
    return;
end

T = T_chk;
if ~ismember("Pass", string(T.Properties.VariableNames))
    T.Pass = false(height(T),1);
end
passV = localToDouble(T.Pass) > 0;
inB = localToDouble(localColumnOrDefault(T, "InputBytes", zeros(height(T),1)));
outB = localToDouble(localColumnOrDefault(T, "OutputBytes", zeros(height(T),1)));
eff = outB ./ max(inB, 1);
status = repmat("PASS", height(T), 1);
status(~passV) = "FAIL";

comp = T;
comp.Pass = passV;
comp.Efficiency = eff;
comp.Status = status;
end

function ctrl = localBuildControlSummary(T_sync, T_e2e)
pbchMin = NaN; pbchMean = NaN;
prachMin = NaN; prachMean = NaN;
pdcchMax = NaN; pdcchMean = NaN;
pucchMax = NaN; pucchMean = NaN;
attachOK = NaN;
attachSlots = NaN;
attachMsgs = NaN;
controlPass = false;
status = "FAIL";
notes = "";

if ~isempty(T_sync)
    pbchMin = localMaybeMin(T_sync, "PBCH_DetectProb");
    pbchMean = localMaybeMean(T_sync, "PBCH_DetectProb");
    prachMin = localMaybeMin(T_sync, "PRACH_DetectProb");
    prachMean = localMaybeMean(T_sync, "PRACH_DetectProb");
    pdcchMax = localMaybeMax(T_sync, "PDCCH_BLER");
    pdcchMean = localMaybeMean(T_sync, "PDCCH_BLER");
    pucchMax = localMaybeMax(T_sync, "PUCCH_BLER");
    pucchMean = localMaybeMean(T_sync, "PUCCH_BLER");
end
if ~isempty(T_e2e)
    attachOK = localMaybeScalar(T_e2e, "AttachSuccess");
    attachSlots = localMaybeScalar(T_e2e, "AttachSlots");
    attachMsgs = localMaybeScalar(T_e2e, "AttachMessages");
end

if ~isnan(pbchMin) && ~isnan(prachMin) && ~isnan(pdcchMax) && ~isnan(pucchMax) && ~isnan(attachOK)
    controlPass = (pbchMin >= 0.99) && (prachMin >= 0.99) && (pdcchMax <= 0.10) && (pucchMax <= 0.10) && (attachOK >= 1);
    if controlPass
        status = "PASS";
    else
        status = "WARN";
    end
else
    status = "WARN";
    notes = "Missing one or more control-path metrics";
end

ctrl = table(pbchMin, pbchMean, prachMin, prachMean, pdcchMax, pdcchMean, ...
    pucchMax, pucchMean, attachOK, attachSlots, attachMsgs, controlPass, status, notes, ...
    'VariableNames', {'PBCHDetectMin','PBCHDetectMean','PRACHDetectMin','PRACHDetectMean', ...
    'PDCCHBLERMax','PDCCHBLERMean','PUCCHBLERMax','PUCCHBLERMean', ...
    'AttachSuccess','AttachSlots','AttachMessages','ControlPathPass','Status','Notes'});
end

function data = localBuildDataSummary(T_slot, T_e2e, stageTotals, compChecks)
offered = NaN; delivered = NaN;
offeredDL = NaN; deliveredDL = NaN;
offeredUL = NaN; deliveredUL = NaN;
delivery = NaN; deliveryDL = NaN; deliveryUL = NaN;
ackRate = NaN; nackRate = NaN; retxProb = NaN;
slots = NaN; slotDur = NaN; simDur = NaN;
componentPassPct = NaN;

if ~isempty(T_e2e)
    offered = localMaybeScalar(T_e2e, "Offered_Mbps");
    delivered = localMaybeScalar(T_e2e, "Goodput_Mbps");
    offeredDL = localMaybeScalar(T_e2e, "OfferedDL_Mbps");
    deliveredDL = localMaybeScalar(T_e2e, "GoodputDL_Mbps");
    offeredUL = localMaybeScalar(T_e2e, "OfferedUL_Mbps");
    deliveredUL = localMaybeScalar(T_e2e, "GoodputUL_Mbps");
    delivery = localMaybeScalar(T_e2e, "DeliveryRatio");
    deliveryDL = localMaybeScalar(T_e2e, "DeliveryRatioDL");
    deliveryUL = localMaybeScalar(T_e2e, "DeliveryRatioUL");
    ackRate = localMaybeScalar(T_e2e, "ACKRate");
    nackRate = localMaybeScalar(T_e2e, "NACKRate");
    retxProb = localMaybeScalar(T_e2e, "HARQ_RetxProbability");
    slots = localMaybeScalar(T_e2e, "NumSlots");
    slotDur = localMaybeScalar(T_e2e, "SlotDuration_ms");
    simDur = localMaybeScalar(T_e2e, "SimulatedDuration_s");
    componentPassPct = localMaybeScalar(T_e2e, "ComponentCheckPassRate_pct");
end
if ~isempty(T_slot)
    if isnan(offered)
        offered = sum(localMaybeColumn(T_slot, "OfferedBits"), "omitnan") / max(localMaybeScalar(T_e2e, "SimulatedDuration_s"), 1) / 1e6;
    end
    if isnan(delivered)
        delivered = sum(localMaybeColumn(T_slot, "DeliveredBits"), "omitnan") / max(localMaybeScalar(T_e2e, "SimulatedDuration_s"), 1) / 1e6;
    end
end

dlActive = all(localDirStageActive(stageTotals, "DL"));
ulActive = all(localDirStageActive(stageTotals, "UL"));
compPassAll = true;
if ~isempty(compChecks) && ismember("Pass", string(compChecks.Properties.VariableNames))
    compPassAll = all(logical(compChecks.Pass));
end
anyDelivered = false;
if ~isempty(T_slot) && ismember("DeliveredBits", string(T_slot.Properties.VariableNames))
    anyDelivered = sum(double(T_slot.DeliveredBits), "omitnan") > 0;
end

overallFlowPass = dlActive && ulActive && compPassAll && anyDelivered;
status = "FAIL";
notes = "";
if overallFlowPass
    if isfinite(delivery) && delivery < 0.01
        status = "WARN";
        notes = "Cross-layer flow passes structural checks but end-to-end delivery ratio is very low.";
    else
        status = "PASS";
    end
else
    status = "FAIL";
    notes = "One or more UL/DL stages have zero flow or component checks failed.";
end

data = table(offered, delivered, offeredDL, deliveredDL, offeredUL, deliveredUL, ...
    delivery, deliveryDL, deliveryUL, ackRate, nackRate, retxProb, ...
    slots, slotDur, simDur, componentPassPct, dlActive, ulActive, compPassAll, ...
    overallFlowPass, status, notes, ...
    'VariableNames', {'OfferedMbps','GoodputMbps','OfferedDLMbps','GoodputDLMbps','OfferedULMbps','GoodputULMbps', ...
    'DeliveryRatio','DeliveryRatioDL','DeliveryRatioUL','ACKRate','NACKRate','RetxProbability', ...
    'NumSlots','SlotDuration_ms','SimDuration_s','ComponentCheckPassRate_pct','DLStageFlowActive','ULStageFlowActive', ...
    'ComponentChecksPass','OverallDataPathPass','Status','Notes'});
end

function act = localDirStageActive(stageTotals, dirName)
if isempty(stageTotals) || ~all(ismember(["Direction","ActiveFlow"], string(stageTotals.Properties.VariableNames)))
    act = false;
    return;
end
mask = stageTotals.Direction == string(dirName);
act = logical(stageTotals.ActiveFlow(mask));
if isempty(act)
    act = false;
end
end

function out = localExtractHighlights(T_lls, T_snr, T_sys, T_harq, T_mmtc, T_v2x, T_ntn, T_intf, T_num, T_beam, T_ai, T_audit, T_e2e)
metric = strings(0,1);
value = strings(0,1);
status = strings(0,1);
notes = strings(0,1);

append("Run.OverallAuditRows", localFmt(height(T_audit)), "INFO", "Rows in 25-category audit");
append("Link.MainBLER_DL", localFmt(localMaybeCaseMetric(T_lls, "DL_PDSCH_Throughput", "BLER")), "INFO", "From lls_kpi_summary");
append("Link.MainBLER_UL", localFmt(localMaybeCaseMetric(T_lls, "UL_PUSCH_Throughput", "BLER")), "INFO", "From lls_kpi_summary");
append("Link.MainThr_DL_Mbps", localFmt(localMaybeCaseMetric(T_lls, "DL_PDSCH_Throughput", "Throughput_Mbps")), "INFO", "From lls_kpi_summary");
append("Link.MainThr_UL_Mbps", localFmt(localMaybeCaseMetric(T_lls, "UL_PUSCH_Throughput", "Throughput_Mbps")), "INFO", "From lls_kpi_summary");
append("Link.SNRSweep.BestDLThr_Mbps", localFmt(localMaybeMax(T_snr, "DL_Throughput_Mbps")), "INFO", "Max over SNR sweep");
append("Link.SNRSweep.BestULThr_Mbps", localFmt(localMaybeMax(T_snr, "UL_Throughput_Mbps")), "INFO", "Max over SNR sweep");
append("System.Throughput_Mbps", localFmt(localMaybeScalar(T_sys, "Throughput_Mbps")), "INFO", "System-level aggregate throughput");
append("System.PacketLoss", localFmt(localMaybeScalar(T_sys, "PacketLoss")), "WARN", "High values indicate heavy load/loss");
append("System.JainFairness", localFmt(localMaybeScalar(T_sys, "JainFairness")), "WARN", "Lower values indicate unfair resource split");
append("HARQ.IR_ResidualBLER", localFmt(localMaybeModeMetric(T_harq, "IR", "HARQ_ResidualBLER")), "INFO", "IR mode residual BLER");
append("HARQ.NoComb_ResidualBLER", localFmt(localMaybeModeMetric(T_harq, "NoComb", "HARQ_ResidualBLER")), "INFO", "No combining baseline");
append("MMTC.AccessSuccessProb", localFmt(localMaybeScalar(T_mmtc, "AccessSuccessProbability")), "INFO", "mMTC access success proxy");
append("V2X.MinPRR_WithComp", localFmt(localMaybeMin(T_v2x, "PacketReceptionRatio_WithComp")), "INFO", "Worst-case PRR with compensation");
append("NTN.MaxCompGain", localFmt(localMaybeMax(T_ntn, "CompensationGain")), "INFO", "Delay/doppler compensation gain");
append("Interference.BLER_at_minSIR", localFmt(localMaybeAtMinX(T_intf, "SIR_dB", "BLER")), "INFO", "BLER at lowest SIR point");
append("Numerology.MaxDLThr_Mbps", localFmt(localMaybeMax(T_num, "DL_Throughput_Mbps")), "INFO", "Best throughput across SCS");
append("Beam.MIMO_Capacity_bpsHz", localFmt(localMaybeScalar(T_beam, "MIMO_Capacity_bpsHz")), "INFO", "MIMO capacity proxy");
append("AI.CSICompression_NMSE_dB", localFmt(localMaybeScalar(T_ai, "CSICompression_NMSE_dB")), "INFO", "AI compression NMSE");
append("E2E.ComponentCheckPassRate_pct", localFmt(localMaybeScalar(T_e2e, "ComponentCheckPassRate_pct")), "INFO", "Cross-layer component checks");
append("E2E.SemanticCheckPassRate_pct", localFmt(localMaybeScalar(T_e2e, "SemanticCheckPassRate_pct")), "INFO", "Packet-level semantic integrity checks");
append("E2E.DeliveryRatio", localFmt(localMaybeScalar(T_e2e, "DeliveryRatio")), "WARN", "Very low ratio indicates congestion/limited grants");
append("E2E.TimeCompressionFactor", localFmt(localMaybeScalar(T_e2e, "TimeCompressionFactor")), "INFO", "Used to cap slot count while preserving 60 s span");
append("E2E.ServiceScaleFactor", localFmt(localMaybeScalar(T_e2e, "ServiceScaleFactor")), "INFO", "Per-slot service scaled to match compression factor");

T = table(metric, value, status, notes, ...
    'VariableNames', {'Metric','Value','Status','Notes'});

out = struct();
out.Table = T;

    function append(m, v, s, n)
        metric(end+1,1) = string(m); %#ok<AGROW>
        value(end+1,1) = string(v); %#ok<AGROW>
        status(end+1,1) = string(s); %#ok<AGROW>
        notes(end+1,1) = string(n); %#ok<AGROW>
    end
end

function v = localMaybeCaseMetric(T, caseName, colName)
v = NaN;
if isempty(T)
    return;
end
vn = string(T.Properties.VariableNames);
if ~all(ismember(["Case", colName], vn))
    return;
end
mask = string(T.Case) == string(caseName);
if any(mask)
    x = T.(colName);
    x = localToDouble(x);
    v = x(find(mask, 1, "first"));
end
end

function v = localMaybeModeMetric(T, modeName, colName)
v = NaN;
if isempty(T)
    return;
end
vn = string(T.Properties.VariableNames);
if ~all(ismember(["Mode", colName], vn))
    return;
end
mask = string(T.Mode) == string(modeName);
if any(mask)
    x = T.(colName);
    x = localToDouble(x);
    v = x(find(mask, 1, "first"));
end
end

function v = localMaybeAtMinX(T, xCol, yCol)
v = NaN;
if isempty(T)
    return;
end
vn = string(T.Properties.VariableNames);
if ~all(ismember([xCol, yCol], vn))
    return;
end
x = localToDouble(T.(xCol));
y = localToDouble(T.(yCol));
if isempty(x) || isempty(y)
    return;
end
[~, idx] = min(x);
if idx >= 1 && idx <= numel(y)
    v = y(idx);
end
end

function localWriteDeepMarkdown(mdFile, runFolder, outFolder, inv, csvCheck, matCheck, figCheck, artRe, flow, kpi, overallOk, controlStatus, dataStatus)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "# Deep Validation Report\n\n");
fprintf(fid, "- Run folder: `%s`\n", runFolder);
fprintf(fid, "- Output folder: `%s`\n", outFolder);
fprintf(fid, "- Generated: `%s`\n\n", char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")));
if overallOk
    overallTxt = "PASS";
else
    overallTxt = "FAIL";
end
fprintf(fid, "- Overall deep validation: `%s`\n", overallTxt);
fprintf(fid, "- Control status: `%s`\n", char(controlStatus));
fprintf(fid, "- Data status: `%s`\n\n", char(dataStatus));

fprintf(fid, "## Artifact Scan\n\n");
fprintf(fid, "- Total files scanned: `%d`\n", inv.TotalFiles);
fprintf(fid, "- CSV files: `%d` (read ok: `%d`, fail: `%d`)\n", csvCheck.Total, csvCheck.ReadOKCount, csvCheck.ReadFailCount);
fprintf(fid, "- MAT files: `%d` (read ok: `%d`, fail: `%d`)\n", matCheck.Total, matCheck.ReadOKCount, matCheck.ReadFailCount);
fprintf(fid, "- Figure files: `%d` (read ok: `%d`, fail: `%d`)\n\n", figCheck.Total, figCheck.ReadOKCount, figCheck.ReadFailCount);

fprintf(fid, "## Revalidated Artifact Checklist\n\n");
fprintf(fid, "- Required coverage (revalidated): `%.2f%%`\n", artRe.RequiredCoverage_pct);
fprintf(fid, "- Missing required artifacts: `%d`\n", round(artRe.MissingRequired));
fprintf(fid, "- Checklist disagreements vs original: `%d`\n\n", round(artRe.DisagreementCount));

if ~isempty(flow.ControlSummary)
    C = flow.ControlSummary(1,:);
    fprintf(fid, "## Control Path Validation\n\n");
    fprintf(fid, "- Status: `%s`\n", char(C.Status));
    fprintf(fid, "- PBCH detect min/mean: `%.6f / %.6f`\n", C.PBCHDetectMin, C.PBCHDetectMean);
    fprintf(fid, "- PRACH detect min/mean: `%.6f / %.6f`\n", C.PRACHDetectMin, C.PRACHDetectMean);
    fprintf(fid, "- PDCCH BLER max/mean: `%.6f / %.6f`\n", C.PDCCHBLERMax, C.PDCCHBLERMean);
    fprintf(fid, "- PUCCH BLER max/mean: `%.6f / %.6f`\n", C.PUCCHBLERMax, C.PUCCHBLERMean);
    fprintf(fid, "- Attach success/slots/messages: `%.0f / %.0f / %.0f`\n\n", C.AttachSuccess, C.AttachSlots, C.AttachMessages);
end

if ~isempty(flow.DataSummary)
    D = flow.DataSummary(1,:);
    fprintf(fid, "## Data Path Validation\n\n");
    fprintf(fid, "- Status: `%s`\n", char(D.Status));
    fprintf(fid, "- Offered Mbps (total/DL/UL): `%.6f / %.6f / %.6f`\n", D.OfferedMbps, D.OfferedDLMbps, D.OfferedULMbps);
    fprintf(fid, "- Goodput Mbps (total/DL/UL): `%.6f / %.6f / %.6f`\n", D.GoodputMbps, D.GoodputDLMbps, D.GoodputULMbps);
    fprintf(fid, "- Delivery ratio (total/DL/UL): `%.9f / %.9f / %.9f`\n", D.DeliveryRatio, D.DeliveryRatioDL, D.DeliveryRatioUL);
    fprintf(fid, "- ACK/NACK/Retx: `%.6f / %.6f / %.6f`\n", D.ACKRate, D.NACKRate, D.RetxProbability);
    fprintf(fid, "- Stage-flow activity DL/UL: `%d / %d`\n", D.DLStageFlowActive, D.ULStageFlowActive);
    fprintf(fid, "- Component checks pass: `%d` (pass-rate field: `%.2f%%`)\n", D.ComponentChecksPass, D.ComponentCheckPassRate_pct);
    if strlength(string(D.Notes)) > 0
        fprintf(fid, "- Notes: %s\n", char(D.Notes));
    end
    fprintf(fid, "\n");
end

fprintf(fid, "## UL/DL Stage Totals\n\n");
fprintf(fid, "| Direction | Stage | Bytes | ActiveFlow |\n");
fprintf(fid, "|---|---|---:|---:|\n");
for i = 1:height(flow.StageTotals)
    fprintf(fid, "| %s | %s | %.0f | %d |\n", ...
        char(flow.StageTotals.Direction(i)), ...
        char(flow.StageTotals.Stage(i)), ...
        double(flow.StageTotals.Bytes(i)), ...
        double(flow.StageTotals.ActiveFlow(i)));
end
fprintf(fid, "\n");

fprintf(fid, "## Component Checks\n\n");
if isempty(flow.ComponentChecks)
    fprintf(fid, "No component check table found.\n\n");
else
    fprintf(fid, "| Direction | Component | InputBytes | OutputBytes | Expected | Pass | Efficiency |\n");
    fprintf(fid, "|---|---|---:|---:|---|---:|---:|\n");
    for i = 1:height(flow.ComponentChecks)
        dirV = localSafeCell(flow.ComponentChecks, "Direction", i);
        compV = localSafeCell(flow.ComponentChecks, "Component", i);
        expV = localSafeCell(flow.ComponentChecks, "ExpectedRelation", i);
        fprintf(fid, "| %s | %s | %.0f | %.0f | %s | %d | %.6f |\n", ...
            char(string(dirV)), char(string(compV)), ...
            double(flow.ComponentChecks.InputBytes(i)), ...
            double(flow.ComponentChecks.OutputBytes(i)), ...
            char(string(expV)), ...
            double(flow.ComponentChecks.Pass(i)), ...
            double(flow.ComponentChecks.Efficiency(i)));
    end
    fprintf(fid, "\n");
end

fprintf(fid, "## KPI Highlights\n\n");
fprintf(fid, "| Metric | Value | Status | Notes |\n");
fprintf(fid, "|---|---:|---|---|\n");
for i = 1:height(kpi.Table)
    fprintf(fid, "| %s | %s | %s | %s |\n", ...
        char(kpi.Table.Metric(i)), char(kpi.Table.Value(i)), ...
        char(kpi.Table.Status(i)), char(kpi.Table.Notes(i)));
end
fprintf(fid, "\n");

fprintf(fid, "## Generated Validation Files\n\n");
fprintf(fid, "- `deep_artifact_inventory.csv`\n");
fprintf(fid, "- `deep_csv_readcheck.csv`\n");
fprintf(fid, "- `deep_mat_readcheck.csv`\n");
fprintf(fid, "- `deep_figure_readcheck.csv`\n");
fprintf(fid, "- `deep_artifact_checklist_revalidated.csv`\n");
fprintf(fid, "- `deep_e2e_stage_totals.csv`\n");
fprintf(fid, "- `deep_e2e_stage_edges.csv`\n");
fprintf(fid, "- `deep_e2e_component_checks_enriched.csv`\n");
fprintf(fid, "- `deep_control_path_summary.csv`\n");
fprintf(fid, "- `deep_data_path_summary.csv`\n");
fprintf(fid, "- `deep_kpi_highlights.csv`\n");
fprintf(fid, "- `deep_validation_summary.mat`\n");
fprintf(fid, "- `deep_validation_report.md`\n");
end

function v = localSafeCell(T, varName, idx)
if ~ismember(varName, string(T.Properties.VariableNames))
    v = "";
    return;
end
col = T.(varName);
if iscell(col)
    v = col{idx};
else
    v = col(idx);
end
end

function st = localSummaryStatus(T)
st = "WARN";
if isempty(T)
    return;
end
if ~ismember("Status", string(T.Properties.VariableNames))
    return;
end
try
    st = upper(string(T.Status(1)));
catch
    st = "WARN";
end
if strlength(st) == 0
    st = "WARN";
end
end

function [numVals, nonFinite] = localNumericCoverage(T)
numVals = 0;
nonFinite = 0;
if isempty(T)
    return;
end
vn = string(T.Properties.VariableNames);
for i = 1:numel(vn)
    c = T.(vn(i));
    if isnumeric(c) || islogical(c)
        x = double(c);
        numVals = numVals + numel(x);
        nonFinite = nonFinite + sum(~isfinite(x(:)));
    end
end
end

function s = localJoinNames(names, maxChars)
if isempty(names)
    s = "";
    return;
end
ss = strjoin(names(:).', "|");
if strlength(ss) > maxChars
    s = extractBefore(ss, maxChars) + "...";
else
    s = ss;
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif isstring(v) || ischar(v)
    x = str2double(string(v));
elseif iscell(v)
    x = str2double(string(v));
else
    x = NaN(size(v));
end
end

function s = localFmt(v)
if isempty(v) || ~isfinite(v)
    s = "NaN";
else
    if abs(v) >= 1e5 || (abs(v) > 0 && abs(v) < 1e-4)
        s = string(sprintf("%.6e", v));
    else
        s = string(sprintf("%.6f", v));
    end
end
end

function v = localMaybeScalar(T, col)
v = NaN;
if isempty(T) || ~ismember(col, string(T.Properties.VariableNames))
    return;
end
x = localToDouble(T.(col));
if isempty(x)
    return;
end
v = x(1);
end

function x = localMaybeColumn(T, col)
if isempty(T) || ~ismember(col, string(T.Properties.VariableNames))
    x = zeros(0,1);
    return;
end
x = localToDouble(T.(col));
end

function v = localMaybeMean(T, col)
v = NaN;
x = localMaybeColumn(T, col);
if ~isempty(x)
    v = mean(x, "omitnan");
end
end

function v = localMaybeMin(T, col)
v = NaN;
x = localMaybeColumn(T, col);
if ~isempty(x)
    v = min(x, [], "omitnan");
end
end

function v = localMaybeMax(T, col)
v = NaN;
x = localMaybeColumn(T, col);
if ~isempty(x)
    v = max(x, [], "omitnan");
end
end

