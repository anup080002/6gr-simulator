function folder=diagnoseMainSharedRA(maxSlots,scenarioPath)
% Exact authored short TDD profile, diagnostic output retained on failure.
% No full-run pass is manufactured by catching an expected integration error.
setup6GRSimToolkit('Verbose',false);
if nargin<1, maxSlots=25; end
validateattributes(maxSlots,{'numeric'},{'scalar','integer','positive','<=',80});
if nargin<2
    scenarioPath=fullfile('simulator','configs','scenarios','lls_causal_access_to_data_wiring_tdd.yaml');
end
s=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
folder=fullfile(tempdir,['main_shared_ra_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
cfg=sixgr.lls6g.buildInternalConfig(s,folder);
assert(strcmpi(sixgr.phy.frame.resolveDuplexMode(cfg),'TDD'),'This diagnostic runs TDD only.');
fprintf('MAIN_SHARED_RA_DIAGNOSTIC=%s\n',folder);
options=struct('LinkSNR_dB',12,'LinkDuration_s',maxSlots*sixgr.time.slotDurationSec(cfg), ...
    'LinkMaxSimFrames',maxSlots,'SaveFigures',false,'PersistenceEnabled',true);
sixgr.truth.runWaveformLinkBundle(cfg,fullfile(folder,'air_interface'),options);
end
