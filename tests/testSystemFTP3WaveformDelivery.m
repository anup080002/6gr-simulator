function ok=testSystemFTP3WaveformDelivery(direction, publicFrontDoor)
% Actual SLS grant decoder -> immutable file ledger -> canonical exports.
if nargin<1, direction="DL"; end
if nargin<2, publicFrontDoor=false; end
direction=string(direction); assert(any(direction==["DL","UL"]));
nTTI=2; if direction=="UL", nTTI=10; end
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
scenario=scenario.toStruct();
scenario.reference_signals.ssb_enabled=false;
scenario.initial_access.ssb.enabled=false;
scenario.reference_signals.pbch_enabled=false;
scenario.initial_access.mib.enabled=false;
scenario.mimo.beam_sweep_enabled=false;
scenario.reference_signals.trs_enabled=false;
scenario.reference_signals.tracking_rs_enabled=false;
scenario.reference_signals.srs_enabled=false;
scenario.control.pucch_enabled=false;
scenario.control.pdcch_enabled=true;
scenario.control.blind_search_enabled=true;
scenario.reference_signals.pdcch_dmrs_enabled=true;
scenario.phy.sib1.enable=false;
scenario.initial_access.sib1.enabled=false;
scenario.mimo.qcl_tci.enabled=false;
scenario.control.connected_dci.tci_present=false;
scenario.channels.pathloss_enabled=false;
scenario.channels.shadow_fading_enabled=false;
scenario.channels.los_enabled=false;
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.run.shortRun=true; cfg.run.strictMode=false; cfg.run.useMex=false;
cfg.run.runTag='ftp3_waveform_delivery'; cfg.run.executionID='ftp3_waveform_delivery';
cfg.system.phyBackend='waveform'; cfg.system.resourceReservations.enabled=true;
cfg.scenario.layout.nSites=1; cfg.scenario.layout.nSectorsPerSite=1;
cfg.scenario.layout.wrapAround=false; cfg.scenario.ue.nUE=1; cfg.scenario.nUE=1;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true; cfg.channel.fading.enable=false;
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false; cfg.channel.losEnabled=false;
cfg.phy.pucch.enable=false; cfg.phy.srs.enable=false; cfg.phy.pdcch.enable=true;
% Dedicated already-connected data/ledger fixture, not an access test.
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.traffic.model='ftp3'; cfg.traffic.ftp3.fileSizeBytes=100;
cfg.traffic.ftp3.arrivalRatePerCell_s=2e4; cfg.traffic.ftp3.direction=direction; cfg.traffic.ftp3.seed=7;
cfg.mac.scheduler.type='rr';
for name=["pdsch","pusch"]
    cfg.phy.(name).numLayers=1; cfg.phy.(name).nLayers=1;
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=120/1024;
end
cfg.outputs.saveCSV=true; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.outputs.saveFIG=false; cfg.outputs.exportSLSOutputCatalog=false;
cfg=sixgr.config.normalizeConfig(cfg); sixgr.config.validateConfig(cfg);
folder=fullfile(pwd,'results','ai_10_3_2_modulation','focused_ftp3_delivery_20261001',lower(direction));
if ~isfolder(folder), mkdir(folder); end
if publicFrontDoor
    cfg.run.mode='system'; cfg.run.useConfigFragments=false;
    cfg.run.numTTI=nTTI; cfg.system.simDuration_s=[];
    cfg.outputs.exportSLSOutputCatalog=true;
    cfg.outputs.saveFigures=true; cfg.outputs.saveFIG=false;
    % The JSON/YAML native request omits the empty MATLAB-only trace table.
    if isfield(cfg.traffic,'trace') && isfield(cfg.traffic.trace,'flowTable') && isempty(cfg.traffic.trace.flowTable)
        cfg.traffic.trace=rmfield(cfg.traffic.trace,'flowTable');
    end
    request=struct('meta',struct('scenario_id','sls_public_waveform_smoke'), ...
        'run_control',struct('execution_mode','SLS'),'sls',struct('config',cfg));
    requestPath=fullfile(folder,'public_sls_request.json');
    sixgr.util.jsonWrite(requestPath,sixgr.util.jsonSafeValue(request));
    publicOut=run_sixgr(requestPath,'results',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
    assert(publicOut.Ok && ~publicOut.PrimaryStudyAccepted);
    folder=char(publicOut.RunFolder); r=publicOut.Result;
    assert(isfile(fullfile(folder,'meta','simulation_run.json')));
    assert(isfile(fullfile(folder,'image','system_throughput_vs_time.png')));
else
    ctx=sixgr.core.SimContext(cfg,'RunFolder',folder);
    cleanup=onCleanup(@()ctx.Logger.close()); %#ok<NASGU>
    r=sixgr.system.SystemLevelRunner.run(ctx,struct('NumTTI',nTTI,'PHYBackend','waveform'));
end
assert(r.Ok,'Dedicated FTP3 waveform runtime failed.');
G=r.Details.SchedulerGrants; F=r.Details.FTP3Files;
assert(~isempty(G) && all(strlength(G.TransportBlockIdentity)>0));
assert(sum(F.DeliveredBits)>0 && any(F.Completed));
assert(sum(F.DeliveredBits)==sum(G.UniqueDeliveredApplicationBits,'omitnan'));
assert(all(F.DeliveredBits+F.DroppedBits+F.RemainingBits==F.OfferedBits));
assert(sum(F.RemainingBits)==sum(r.Details.RemainingQueueBits));
assert(isfile(fullfile(folder,'csv','system_resource_reservations.csv')));
writetable(F,fullfile(folder,'ftp3_file_lifecycle.csv'));
writetable(r.Details.FTP3DeliveryEvents,fullfile(folder,'ftp3_delivery_events.csv'));
writetable(r.Details.FTP3UserMetrics,fullfile(folder,'ftp3_user_metrics.csv'));
scfg=sixgr.lls6g.config.ScenarioConfig(scenario);
sixgr.truth.exportSystemLevelCanonicalArtifacts(folder,scfg,cfg,r);
assert(isfile(fullfile(folder,'system','csv','ftp3_file_lifecycle.csv')));
trialName="dl_pdsch_trials.csv";
if direction=="UL", trialName="ul_pusch_trials.csv"; end
published=readtable(fullfile(folder,'air_interface','csv',trialName),'TextType','string');
assert(height(published)==height(G));
assert(all(published.TransportBlockIdentity==G.TransportBlockIdentity));
assert(isequal(published.ApplicationPayloadBits,G.ApplicationPayloadBits));
assert(isequal(published.UniqueDeliveredApplicationBits,G.UniqueDeliveredApplicationBits));
assert(sum(published.GoodBits)==sum(F.DeliveredBits));
assert(all(published.GoodputDefinition== ...
    "unique_first_success_application_payload_excluding_padding"));
sixgr.report.exportSLSOutputCatalog(folder,cfg,r,r.RuntimeSummary,r.EnvironmentSummary);
assert(isfile(fullfile(folder,'traces','ftp3_file_lifecycle.csv')));
ok=true;
fprintf('SYSTEM_FTP3_WAVEFORM_DELIVERY_PASS direction=%s grants=%d completed_files=%d delivered_bits=%g folder=%s\n',direction,height(G),nnz(F.Completed),sum(F.DeliveredBits),folder);
end
