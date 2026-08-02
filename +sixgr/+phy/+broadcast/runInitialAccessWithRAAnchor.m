function out = runInitialAccessWithRAAnchor(runFolder, cfg, varargin)
%RUNINITIALACCESSWITHRAANCHOR Run SSB/PBCH/SIB1 then four-step RA.

p = inputParser;
p.addParameter("RunId", "initial_access_ra_anchor", @(x) ischar(x) || isstring(x));
p.addParameter("ScenarioName", "lls_initial_access_ra_anchor", @(x) ischar(x) || isstring(x));
p.addParameter("SNRdB", 35, @(x) isnumeric(x) && isscalar(x));
p.addParameter("Seed", 1501, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});

if nargin < 1 || strlength(string(runFolder)) == 0
    runFolder = fullfile(tempdir, "sixgr_initial_access_ra_anchor");
end
if nargin < 2 || isempty(cfg)
    cfg = sixgr.config.defaultConfig();
end

cfg = localPrepareInitialAccessCfg(cfg);
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    "SNRdB", double(p.Results.SNRdB), "Seed", double(p.Results.Seed));
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg);
sib1Artifacts = sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(runFolder, tx, rx);

ra = sixgr.phy.ra.runFourStepRA(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(p.Results.RunId), ...
    "ScenarioName", string(p.Results.ScenarioName), ...
    "UEId", 1, ...
    "CellId", sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1), ...
    "AttemptId", 1, ...
    "SIB1Recovery", rx, ...
    "RequireDecodedSIB1", true, ...
    "WriteArtifacts", true);

out = struct();
out.Ok = logical(rx.StrictOk) && logical(ra.StrictOk);
out.SIB1Ok = logical(rx.StrictOk);
out.RAOk = logical(ra.StrictOk);
out.RunFolder = string(runFolder);
out.Tx = tx;
out.SIB1 = rx;
out.RandomAccess = ra;
out.SIB1Artifacts = sib1Artifacts;
out.FailureReason = "";
if ~logical(out.Ok)
    out.FailureReason = strjoin([string(rx.FailureReason), string(ra.FailureReason)], "|");
end
end

function cfg = localPrepareInitialAccessCfg(cfg)
cfg.run.strictMode = true;
required = ["ssb", "pbch", "pdcch", "sib1", "prach"];
paths = ["phy.ssb.enable", "phy.pbch.enable", "phy.pdcch.enable", ...
    "phy.sib1.enable", "phy.prach.enable"];
for featureIndex = 1:numel(required)
    value = logical(sixgr.util.structGet(cfg, paths(featureIndex), false));
    if isfield(cfg, "runtime") && isfield(cfg.runtime, "features")
        sixgr.config.assertRuntimeFeatureUse(cfg, required(featureIndex), ...
            value, "runInitialAccessWithRAAnchor");
    end
    if ~value
        error("sixgr:phy:broadcast:InitialAccessFeatureDisabledByYAML", ...
            "Integrated initial access requires configured feature %s=true.", ...
            char(required(featureIndex)));
    end
end
cfg.phy.sib1.ssbObservationSubframes = double(sixgr.util.structGet(cfg, "phy.sib1.ssbObservationSubframes", 5));
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 17));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30)));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, ...
    "phy.carrier.NSizeGrid", 51));
if ~isfield(cfg, "random_access") || ~isstruct(cfg.random_access)
    error("sixgr:phy:broadcast:MissingRandomAccessForInitialAccess", ...
        "Integrated initial-access/RA anchor requires explicit random_access config.");
end
cfg = localMirrorRandomAccessIntoSIB1Prach(cfg);
end

function cfg = localMirrorRandomAccessIntoSIB1Prach(cfg)
ra = cfg.random_access;
cfg = sixgr.util.structSet(cfg, "phy.prach.configurationIndex", ...
    double(sixgr.util.structGet(ra, "configuration_index", ...
    sixgr.util.structGet(cfg, "phy.prach.configurationIndex", 16))));
cfg = sixgr.util.structSet(cfg, "phy.prach.rootSeqIndex", ...
    double(sixgr.util.structGet(ra, "root_sequence_index", ...
    sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", 1))));
cfg = sixgr.util.structSet(cfg, "phy.prach.zeroCorrelationZone", ...
    double(sixgr.util.structGet(ra, "zero_correlation_zone", ...
    sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", 8))));
cfg = sixgr.util.structSet(cfg, "phy.prach.nPreambles", ...
    double(sixgr.util.structGet(ra, "preamble_count", ...
    sixgr.util.structGet(cfg, "phy.prach.nPreambles", 64))));
cfg = sixgr.util.structSet(cfg, "phy.prach.preambleFormat", ...
    string(sixgr.util.structGet(ra, "prach_format", ...
    sixgr.util.structGet(cfg, "phy.prach.preambleFormat", "0"))));
cfg = sixgr.util.structSet(cfg, "phy.prach.restrictedSet", ...
    string(sixgr.util.structGet(ra, "restricted_set", ...
    sixgr.util.structGet(cfg, "phy.prach.restrictedSet", "UnrestrictedSet"))));
cfg = sixgr.util.structSet(cfg, "phy.prach.subcarrierSpacing_kHz", ...
    double(sixgr.util.structGet(ra, "subcarrier_spacing_khz", ...
    sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", cfg.phy.carrier.SubcarrierSpacing))));
end
