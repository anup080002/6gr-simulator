function [evidence,raw,audit]=loadLLSEnergyResourceEvidence(cfg,airFolder,raw)
% Normal live/final export wiring, including restored historical prefixes.
% Read the executed ledger only. Cache compact intervals by CONTENT hash,
% grid and parser source, never file existence/size/mtime or planned mapping.
% This does not load checkpoint state or launch a waveform simulation.
persistent cachedKey cachedIntervals cachedAudit
evidence=[]; audit=struct('ResourceLedgerAvailable',false,'CacheHit',false, ...
    'SourceSHA256',"",'ResourceRows',0,'IntervalRows',0,'RAStageSourceSHA256',"", ...
    'ReadSeconds',0,'PhysicalReplayExecuted',false);
layout=sixgr.report.resultLayout(fileparts(char(string(airFolder))));
path=string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv'));
native=string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_prach_native_allocation.csv'));
ssb=string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_ssb_native_allocation.csv'));
if ~any(isfile([path native ssb])), return; end
timer=tic;
configHash=string(sixgr.util.structGet(cfg,'meta.configHash',""));
assert(~ismissing(configHash)&&strlength(configHash)>0, ...
    'sixgr:truth:EnergyResourceConfigIdentity','Executed energy resources require the run configuration hash.');
carrier=nrCarrierConfig('NSizeGrid',cfg.phy.carrier.NSizeGrid, ...
    'SubcarrierSpacing',cfg.phy.carrier.SubcarrierSpacing, ...
    'CyclicPrefix',char(sixgr.util.structGet(cfg,'phy.carrier.CyclicPrefix',"normal")));
hash=""; R=table(); a=struct('SourceRows',0);
if isfile(path)
hash=string(sixgr.util.sha256File(path));
parserHash=string(sixgr.util.sha256File(which('sixgr.truth.readObservedOFDMResourceIntervals')));
key=hash+"|"+configHash+"|"+carrier.NSizeGrid+"|"+carrier.SubcarrierSpacing+"|"+carrier.CyclicPrefix+"|"+parserHash;
if ~isempty(cachedKey) && key==cachedKey
    R=cachedIntervals; a=cachedAudit; audit.CacheHit=true;
else
    [R,a]=sixgr.truth.readObservedOFDMResourceIntervals(path,hash,carrier,32768);
    cachedKey=key; cachedIntervals=R; cachedAudit=a;
end
end
evidence=struct('Intervals',R,'ConfigHash',configHash,'SourceSHA256',hash);
if isfile(native)
    [evidence.NativePRACH,evidence.NativeSourceSHA256]=verifiedTable(native);
end
if isfile(ssb)
    [evidence.NativeSSB,evidence.NativeSSBSourceSHA256]=verifiedTable(ssb);
end
% Normal calls carry in-memory completed RA tables. Terminal/report-only
% calls recover the exact persisted stages from the same run folder.
if isempty(sixgr.util.structGet(raw,'RAEvidenceTables.ra_runtime_stage_waveforms',table()))
    stagePath=string(fullfile(layout.ControlCSVDir,'ra_runtime_stage_waveforms.csv'));
    if isfile(stagePath)
        [raw.RAEvidenceTables.ra_runtime_stage_waveforms,audit.RAStageSourceSHA256]=verifiedTable(stagePath);
    end
end
if strlength(hash)>0
    assert(isfile(path) && string(sixgr.util.sha256File(path))==hash, ...
        'sixgr:truth:EnergyResourceChangedDuringRead','Executed resource ledger changed during export.');
end
audit.ResourceLedgerAvailable=true; audit.SourceSHA256=hash;
audit.ResourceRows=a.SourceRows; audit.IntervalRows=height(R); audit.ReadSeconds=toc(timer);
end

function [T,hash]=verifiedTable(path)
hash=string(sixgr.util.sha256File(path));
T=sixgr.util.csvReadTable(path,'TextType','string');
assert(string(sixgr.util.sha256File(path))==hash, ...
    'sixgr:truth:EnergyResourceChangedDuringRead','Executed evidence changed during export: %s.',path);
end
