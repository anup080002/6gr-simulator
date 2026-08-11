function ok = testRAN1LLSISAC()
%TESTRAN1LLSISAC Focused communication-centric ISAC production checks.

[cfg,~] = sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_isac_monostatic_30ghz_example.yaml");
assert(cfg.isac.enabled);
assert(string(cfg.isac.waveformAuthority) == "exact_runtime_pdsch_waveform");
assert(string(cfg.isac.channelModel) == "phased_scattering_mimo");

state = sixgr.lls.resolveAntennaState(cfg);
assert(state.Tx.NumElements == 16);
assert(state.Rx.NumElements == 4);

% A shorter coherent capture keeps this dedicated regression bounded while
% still running the production PDSCH transmitter and sensing channel.
testCfg = cfg;
testCfg.isac.coherentRepetitions = 2;
phyCfg = sixgr.lls.buildPHYConfig(testCfg,35);
[tx,~] = sixgr.phy.dl.PDSCH_Tx(phyCfg, ...
    "ExecutionProfile","phy_calibration", ...
    "NumTxAnt",double(testCfg.pdsch.numberAntennaPorts), ...
    "CompactOutput",false);
sensing = sixgr.lls.runISACSensingTrial(testCfg,tx);
assert(sensing.EvidenceValid);
assert(height(sensing.TargetTruthTable) == 1);
assert(~isempty(sensing.DetectionTable));
assert(sensing.RuntimeTable.MatchedTargetCount(1) >= 1);
assert(sensing.RuntimeTable.RangeRMSEM(1) <= ...
    testCfg.isac.acceptance.maximumRangeErrorM);
assert(sensing.RuntimeTable.AzimuthRMSEDeg(1) <= ...
    testCfg.isac.acceptance.maximumAzimuthErrorDeg);
assert(strlength(sensing.LogicalWaveformSHA256) == 64);
assert(strlength(sensing.ReceivedSensingCubeSHA256) == 64);
assert(isequal(double(sensing.GNBPositionM(:)),double(testCfg.isac.scene.gnbPositionM(:))) && ...
    isequal(double(sensing.UEPositionM(:)),double(testCfg.isac.scene.uePositionM(:))));
assert(all(ismember(["GNBX_m","GNBY_m","GNBZ_m","UEX_m","UEY_m","UEZ_m"], ...
    string(sensing.ConfigTable.Properties.VariableNames))));

folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() localRemoveTree(folder)); %#ok<NASGU>
paths = sixgr.lls.exportISACArtifacts(folder,testCfg, ...
    struct("ISAC",sensing),true);
assert(numel(paths) == 4);
assert(numel(dir(fullfile(folder,"isac_*.csv"))) == 9);
assert(numel(dir(fullfile(folder,"isac_*.png"))) == 4);
assert(isempty(dir(fullfile(folder,"*.svg"))));
lineage = readtable(fullfile(folder,"isac_plot_lineage.csv"), ...
    "TextType","string","VariableNamingRule","preserve");
assert(height(lineage) == 4 && all(strcmpi(lineage.Status,"pass")));
assert(all(strlength(lineage.SourceCSV_SHA256) >= 64) && ...
    all(strlength(lineage.ImageSHA256) == 64));

% Full-stack scenarios own node positions through runtime topology rather
% than duplicating them under isac.scene.  Artifact publication must use
% the executed sensing evidence, not fall back to configured coordinates.
structuredCfg = testCfg;
structuredCfg.isac.scene = rmfield(structuredCfg.isac.scene, ...
    {'gnbPositionM','uePositionM'});
structuredCfg.isac.output.structuredComponentFolders = true;
structuredPaths = sixgr.lls.exportISACArtifacts(folder,structuredCfg, ...
    struct("ISAC",sensing),true,struct("StructuredComponentFolders",true));
assert(numel(structuredPaths) == 4);
assert(numel(dir(fullfile(folder,"isac","csv","*.csv"))) == 9);
assert(numel(dir(fullfile(folder,"isac","image","*.png"))) == 4);
for csvFile = dir(fullfile(folder,"isac","csv","*.csv")).'
    fid = fopen(fullfile(csvFile.folder,csvFile.name),'r');
    assert(fid >= 0,"Unable to open ISAC CSV %s.",csvFile.name);
    headerLine = fgetl(fid);
    fclose(fid);
    header = string(strsplit(headerLine,','));
    assert(numel(unique(lower(header))) == numel(header), ...
        "ISAC CSV %s contains case-insensitive duplicate columns.",csvFile.name);
end

% Reproduce the production ordering hazard: scenario-wide provenance
% annotation changes source CSV bytes after the sensing images were
% rendered.  Refresh must rebind all four images to those finalized bytes.
targetPath = fullfile(folder,"isac","csv","isac_target_truth.csv");
annotatedTarget = readtable(targetPath,"TextType","string", ...
    "VariableNamingRule","preserve");
annotatedTarget.RuntimeAnnotation = repmat("finalized",height(annotatedTarget),1);
writetable(annotatedTarget,targetPath);
auditBeforeRefresh = sixgr.visual.verifyVisualArtifacts(folder,table());
assert(any(~auditBeforeRefresh.IntegrityOk & ...
    auditBeforeRefresh.FailureCode == "component_plot_source_hash_mismatch"));
refreshedLineage = sixgr.lls.refreshISACPlotLineage(folder,structuredCfg);
assert(height(refreshedLineage) == 4 && all(refreshedLineage.Status == "pass"));
auditAfterRefresh = sixgr.visual.verifyVisualArtifacts(folder,table());
assert(~isempty(auditAfterRefresh) && all(auditAfterRefresh.IntegrityOk));

invalid = cfg;
[puschCfg,~] = sixgr.lls.loadConfig("configs/lls/pusch_reference.yaml");
invalid.simulation.link = "PUSCH";
invalid.pusch = puschCfg.pusch;
invalid.channel.txAntennas = 4;
invalid.channel.rxAntennas = 16;
localAssertError(@() sixgr.lls.validateConfig(invalid), ...
    "sixgr:lls:ISACRequiresPDSCH");

fprintf("testRAN1LLSISAC: PASS\n");
ok = true;
end

function localAssertError(callback,identifier)
try
    callback();
    error("testRAN1LLSISAC:MissingError", ...
        "Expected typed error %s.",identifier);
catch ME
    if strcmp(ME.identifier,"testRAN1LLSISAC:MissingError")
        rethrow(ME);
    end
    assert(strcmp(ME.identifier,identifier), ...
        "Expected %s, received %s: %s",identifier,ME.identifier,ME.message);
end
end

function localRemoveTree(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
