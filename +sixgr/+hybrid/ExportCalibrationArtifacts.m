function out = ExportCalibrationArtifacts(runFolder, calib, varargin)
%EXPORTCALIBRATIONARTIFACTS Write standardized calibration artifacts.
%
% Artifacts written under <runFolder>/calibration:
%   - bler_db.mat
%   - bler_db_metadata.json
%   - calibration_coverage.csv
%   - calibration_validation.csv

if nargin < 2 || isempty(calib)
    calib = struct();
end

p = inputParser;
p.addParameter("StrictMode", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
p.addParameter("SourceRun", "", @(x)ischar(x)||isstring(x));
p.addParameter("TrialCounts", struct(), @(x)isstruct(x));
p.parse(varargin{:});
opt = p.Results;

calDir = fullfile(char(string(runFolder)), "calibration");
sixgr.util.ensureDir(calDir);

[db, pointTable, calibSource] = localResolveCalibrationPayload(calib);
coverage = localBuildCoverageTable(pointTable);
validation = localBuildValidationTable(db, pointTable, logical(opt.StrictMode));

missingPoints = sum(~isfinite(double(pointTable.BLER)));
totalPoints = height(pointTable);
coveragePct = 100 * (1 - double(missingPoints) / max(1, double(totalPoints)));

meta = struct();
meta.generatedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
meta.strictMode = logical(opt.StrictMode);
meta.sourceRun = char(string(opt.SourceRun));
meta.calibrationSource = char(string(calibSource));
meta.axes = localAxesToMetadata(db.Axes);
meta.trialCounts = opt.TrialCounts;
meta.totalPoints = double(totalPoints);
meta.missingPoints = double(missingPoints);
meta.coveragePct = double(coveragePct);
meta.interpolationQuality = localInterpolationQuality(validation);

matFile = fullfile(calDir, "bler_db.mat");
jsonFile = fullfile(calDir, "bler_db_metadata.json");
covCsv = fullfile(calDir, "calibration_coverage.csv");
valCsv = fullfile(calDir, "calibration_validation.csv");

payload = struct();
payload.DB = db;
payload.PointTable = pointTable;
payload.CoverageTable = coverage;
payload.ValidationTable = validation;
payload.Metadata = meta;
payload.Calibration = calib;
sixgr.util.matSave(matFile, payload);
sixgr.util.jsonWrite(jsonFile, meta);
sixgr.util.csvWriteTable(covCsv, coverage);
sixgr.util.csvWriteTable(valCsv, validation);

out = struct();
out.Ok = true;
out.RunFolder = char(string(runFolder));
out.CalibrationFolder = calDir;
out.BLERDBMat = matFile;
out.MetadataJSON = jsonFile;
out.CoverageCSV = covCsv;
out.ValidationCSV = valCsv;
out.Source = string(calibSource);
out.CoveragePct = double(coveragePct);
out.MissingPoints = double(missingPoints);
out.TotalPoints = double(totalPoints);
end

function [db, pointTable, calibSource] = localResolveCalibrationPayload(calib)
if isfield(calib, "DB") && ~isempty(calib.DB)
    db = sixgr.system.BLER_DB(calib.DB);
    pointTable = localPointTableFromDB(db);
    calibSource = string(sixgr.util.structGet(calib.DB, "Source", ...
        sixgr.util.structGet(calib, "Source", "db_payload")));
    if isfield(calib, "Table") && istable(calib.Table) && ~isempty(calib.Table)
        pointTable = localNormalizePointTable(calib.Table, db);
    end
    return;
end

if isfield(calib, "LUT") && ~isempty(calib.LUT)
    lut = sixgr.system.BLER_LUT(calib.LUT);
    [db, pointTable] = localDBFromLUT(lut);
    calibSource = string(sixgr.util.structGet(calib.LUT, "Source", ...
        sixgr.util.structGet(calib, "Source", "lut_payload")));
    return;
end

if isfield(calib, "DL") || isfield(calib, "UL")
    [db, pointTable] = localDBFromDualDirection(calib);
    calibSource = string(sixgr.util.structGet(calib, "Source", "dual_direction_payload"));
    return;
end

lut = sixgr.system.BLER_LUT();
[db, pointTable] = localDBFromLUT(lut);
calibSource = "fallback_default_lut";
end

function [db, T] = localDBFromLUT(lut)
snr = double(lut.SNR_dB(:));
bler = double(lut.BLER(:));
b = zeros(2,1,1,1,1,1,1,numel(snr));
b(1,1,1,1,1,1,1,:) = reshape(bler, 1,1,1,1,1,1,1,[]);
b(2,1,1,1,1,1,1,:) = reshape(bler, 1,1,1,1,1,1,1,[]);
db = sixgr.system.BLER_DB("SNR_dB", snr, "Direction", ["DL","UL"], ...
    "MCS", 0, "PRB", 50, "Layers", 1, "SCS", 30, "DopplerHz", 0, ...
    "ChannelModel", "AWGN", "BLER", b, "Source", "lut_replicated");
T = localPointTableFromDB(db);
end

function [db, T] = localDBFromDualDirection(calib)
dl = sixgr.util.structGet(calib, "DL", struct());
ul = sixgr.util.structGet(calib, "UL", struct());
snrDL = double(sixgr.util.structGet(dl, "SNR_dB", []));
snrUL = double(sixgr.util.structGet(ul, "SNR_dB", []));
blerDL = double(sixgr.util.structGet(dl, "BLER", []));
blerUL = double(sixgr.util.structGet(ul, "BLER", []));

snrAxis = unique([snrDL(:); snrUL(:)]);
if isempty(snrAxis)
    lut = sixgr.system.BLER_LUT();
    [db, T] = localDBFromLUT(lut);
    return;
end
snrAxis = sort(double(snrAxis(:)));
if isempty(blerDL)
    blerDL = interp1(snrUL(:), blerUL(:), snrAxis, "linear", "extrap");
else
    blerDL = interp1(snrDL(:), blerDL(:), snrAxis, "linear", "extrap");
end
if isempty(blerUL)
    blerUL = interp1(snrDL(:), blerDL(:), snrAxis, "linear", "extrap");
else
    blerUL = interp1(snrUL(:), blerUL(:), snrAxis, "linear", "extrap");
end
if any(~isfinite(blerDL)) || any(~isfinite(blerUL))
    lut = sixgr.system.BLER_LUT("SNR_dB", snrAxis);
    if any(~isfinite(blerDL)), blerDL(~isfinite(blerDL)) = lut.BLER(~isfinite(blerDL)); end
    if any(~isfinite(blerUL)), blerUL(~isfinite(blerUL)) = lut.BLER(~isfinite(blerUL)); end
end
blerDL = localClampMonotonic(blerDL(:));
blerUL = localClampMonotonic(blerUL(:));

b = zeros(2,1,1,1,1,1,1,numel(snrAxis));
b(1,1,1,1,1,1,1,:) = reshape(blerDL, 1,1,1,1,1,1,1,[]);
b(2,1,1,1,1,1,1,:) = reshape(blerUL, 1,1,1,1,1,1,1,[]);
db = sixgr.system.BLER_DB("SNR_dB", snrAxis, "Direction", ["DL","UL"], ...
    "MCS", 0, "PRB", 50, "Layers", 1, "SCS", 30, "DopplerHz", 0, ...
    "ChannelModel", "AWGN", "BLER", b, "Source", "dual_direction_curve");
T = localPointTableFromDB(db);
end

function v = localClampMonotonic(v)
v = double(v(:));
v = min(max(v, 1e-4), 0.9999);
for i = 2:numel(v)
    v(i) = min(v(i), v(i-1));
end
end

function T = localPointTableFromDB(db)
a = db.Axes;
B = db.BLER;
rows = numel(a.Direction) * numel(a.MCS) * numel(a.PRB) * numel(a.Layers) * ...
    numel(a.SCS) * numel(a.DopplerHz) * numel(a.ChannelModel) * numel(a.SNR_dB);

Direction = strings(rows,1);
MCSIndex = zeros(rows,1);
PRB = zeros(rows,1);
Layers = zeros(rows,1);
SCS_kHz = zeros(rows,1);
DopplerHz = zeros(rows,1);
ChannelModel = strings(rows,1);
SNR_dB = zeros(rows,1);
BLER = zeros(rows,1);
SkippedPoint = false(rows,1);

idx = 0;
for iDir = 1:numel(a.Direction)
    for iM = 1:numel(a.MCS)
        for iP = 1:numel(a.PRB)
            for iL = 1:numel(a.Layers)
                for iS = 1:numel(a.SCS)
                    for iD = 1:numel(a.DopplerHz)
                        for iC = 1:numel(a.ChannelModel)
                            for iN = 1:numel(a.SNR_dB)
                                idx = idx + 1;
                                Direction(idx) = string(a.Direction(iDir));
                                MCSIndex(idx) = double(a.MCS(iM));
                                PRB(idx) = double(a.PRB(iP));
                                Layers(idx) = double(a.Layers(iL));
                                SCS_kHz(idx) = double(a.SCS(iS));
                                DopplerHz(idx) = double(a.DopplerHz(iD));
                                ChannelModel(idx) = string(a.ChannelModel(iC));
                                SNR_dB(idx) = double(a.SNR_dB(iN));
                                BLER(idx) = double(B(iDir,iM,iP,iL,iS,iD,iC,iN));
                                SkippedPoint(idx) = false;
                            end
                        end
                    end
                end
            end
        end
    end
end
T = table(Direction, MCSIndex, PRB, Layers, SCS_kHz, DopplerHz, ChannelModel, ...
    SNR_dB, BLER, SkippedPoint);
end

function T = localNormalizePointTable(Tin, db)
T = Tin;
vars = {'Direction','MCSIndex','PRB','Layers','SCS_kHz','DopplerHz','ChannelModel','SNR_dB','BLER','SkippedPoint'};
for i = 1:numel(vars)
    v = vars{i};
    if ~ismember(v, T.Properties.VariableNames)
        switch v
            case {'Direction','ChannelModel'}
                T.(v) = strings(height(T),1);
            case 'SkippedPoint'
                T.(v) = false(height(T),1);
            otherwise
                T.(v) = NaN(height(T),1);
        end
    end
end
T = T(:, vars);
if all(strlength(string(T.Direction)) == 0)
    T.Direction(:) = string(db.Axes.Direction(1));
end
if all(strlength(string(T.ChannelModel)) == 0)
    T.ChannelModel(:) = string(db.Axes.ChannelModel(1));
end
end

function C = localBuildCoverageTable(T)
if isempty(T)
    C = table();
    return;
end
keyVars = {'Direction','MCSIndex','PRB','Layers','SCS_kHz','DopplerHz','ChannelModel'};
[G, keyTbl] = findgroups(T(:, keyVars));
n = height(keyTbl);
PointsExpected = zeros(n,1);
PointsPresent = zeros(n,1);
PointsMissing = zeros(n,1);
Missing_pct = zeros(n,1);
SkippedPoints = zeros(n,1);

for g = 1:n
    m = (G == g);
    snrUnique = unique(double(T.SNR_dB(m)));
    expPts = numel(snrUnique);
    present = sum(isfinite(double(T.BLER(m))));
    miss = max(0, expPts - present);
    skp = 0;
    if ismember('SkippedPoint', T.Properties.VariableNames)
        skp = sum(logical(T.SkippedPoint(m)));
    end
    PointsExpected(g) = expPts;
    PointsPresent(g) = present;
    PointsMissing(g) = miss;
    Missing_pct(g) = 100 * double(miss) / max(1, double(expPts));
    SkippedPoints(g) = skp;
end

C = keyTbl;
C.PointsExpected = PointsExpected;
C.PointsPresent = PointsPresent;
C.PointsMissing = PointsMissing;
C.Missing_pct = Missing_pct;
C.SkippedPoints = SkippedPoints;
end

function V = localBuildValidationTable(db, T, strictMode)
B = double(db.BLER);
allFinite = all(isfinite(B), 'all');
minB = min(B, [], 'all');
maxB = max(B, [], 'all');
rangeOk = isfinite(minB) && isfinite(maxB) && (minB >= 1e-4) && (maxB <= 0.9999);
missing = sum(~isfinite(B), 'all');
total = numel(B);
coveragePct = 100 * (1 - double(missing) / max(1, double(total)));

monotonicViol = localCountMonotonicViolations(B);
[rmse, mae, maxAbs] = localInterpolationError(db, T);

Metric = ["StrictMode"; "AllFinitePoints"; "CoveragePct"; "MissingPoints"; ...
    "BLERRangeValid"; "MonotonicViolations"; "InterpolationRMSE"; ...
    "InterpolationMAE"; "InterpolationMaxAbs"];
Value = [double(logical(strictMode)); double(allFinite); double(coveragePct); double(missing); ...
    double(rangeOk); double(monotonicViol); double(rmse); double(mae); double(maxAbs)];
Threshold = [double(logical(strictMode)); 1; 99.0; 0; 1; 0; 0.05; 0.02; 0.10];
Pass = [true; logical(allFinite); coveragePct >= 99.0; missing == 0; logical(rangeOk); ...
    monotonicViol == 0; rmse <= 0.05; mae <= 0.02; maxAbs <= 0.10];
Notes = strings(numel(Metric),1);
Notes(1) = "Strict mode status used during calibration query policy.";
Notes(2) = "All BLER tensor points finite.";
Notes(3) = "Percent finite BLER points in tensor.";
Notes(4) = "Count of non-finite BLER points.";
Notes(5) = "BLER clipped to [1e-4, 0.9999].";
Notes(6) = "Count of contexts where BLER increased with SNR.";
Notes(7) = "RMSE between table BLER and DB queried BLER.";
Notes(8) = "MAE between table BLER and DB queried BLER.";
Notes(9) = "Max abs error between table BLER and DB queried BLER.";

V = table(Metric, Value, Threshold, Pass, Notes);
end

function nViol = localCountMonotonicViolations(B)
sz = size(B);
if numel(sz) < 8
    B = reshape(B, [sz, ones(1,8-numel(sz))]);
    sz = size(B);
end
nViol = 0;
for iDir = 1:sz(1)
    for iM = 1:sz(2)
        for iP = 1:sz(3)
            for iL = 1:sz(4)
                for iS = 1:sz(5)
                    for iD = 1:sz(6)
                        for iC = 1:sz(7)
                            c = squeeze(B(iDir,iM,iP,iL,iS,iD,iC,:));
                            c = c(:);
                            if numel(c) < 2
                                continue;
                            end
                            dv = diff(c);
                            nViol = nViol + sum(dv > 1e-9);
                        end
                    end
                end
            end
        end
    end
end
end

function [rmse, mae, maxAbs] = localInterpolationError(db, T)
if isempty(T)
    rmse = NaN; mae = NaN; maxAbs = NaN;
    return;
end
pred = NaN(height(T),1);
for i = 1:height(T)
    ctx = struct();
    ctx.Direction = string(T.Direction(i));
    ctx.SINR_dB = double(T.SNR_dB(i));
    ctx.MCSIndex = double(T.MCSIndex(i));
    ctx.PRBCount = double(T.PRB(i));
    ctx.NumLayers = double(T.Layers(i));
    ctx.SCS_kHz = double(T.SCS_kHz(i));
    ctx.DopplerHz = double(T.DopplerHz(i));
    ctx.ChannelModel = string(T.ChannelModel(i));
    pred(i) = sixgr.system.BLER_DB("query", db, ctx, false);
end
err = pred - double(T.BLER);
err = err(isfinite(err));
if isempty(err)
    rmse = NaN; mae = NaN; maxAbs = NaN;
    return;
end
rmse = sqrt(mean(err.^2));
mae = mean(abs(err));
maxAbs = max(abs(err));
end

function q = localInterpolationQuality(V)
q = struct();
q.rmse = localValidationValue(V, "InterpolationRMSE");
q.mae = localValidationValue(V, "InterpolationMAE");
q.maxAbs = localValidationValue(V, "InterpolationMaxAbs");
q.monotonicViolations = localValidationValue(V, "MonotonicViolations");
q.coveragePct = localValidationValue(V, "CoveragePct");
end

function v = localValidationValue(V, name)
v = NaN;
if isempty(V)
    return;
end
i = find(string(V.Metric) == string(name), 1, "first");
if isempty(i)
    return;
end
v = double(V.Value(i));
end

function a = localAxesToMetadata(ax)
a = struct();
a.Direction = string(ax.Direction(:).');
a.MCS = double(ax.MCS(:).');
a.PRB = double(ax.PRB(:).');
a.Layers = double(ax.Layers(:).');
a.SCS_kHz = double(ax.SCS(:).');
a.DopplerHz = double(ax.DopplerHz(:).');
a.ChannelModel = string(ax.ChannelModel(:).');
a.SNR_dB = double(ax.SNR_dB(:).');
end
