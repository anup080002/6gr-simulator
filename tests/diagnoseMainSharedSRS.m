function folder=diagnoseMainSharedSRS()
% YAML-owned duration, operating point and output flags; TDD diagnostic only.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_tdd_shared_srs_fixture.yaml'));
folder=fullfile(tempdir,['main_shared_srs_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
assert(sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD");
slots=double(source.get('run_control.total_slots'));
options=struct('LinkSNR_dB',double(cfg.channel.snr_dB), ...
    'LinkDuration_s',slots*sixgr.time.slotDurationSec(cfg),'LinkMaxSimFrames',slots, ...
    'SaveFigures',logical(source.get('output.save_figures')), ...
    'PersistenceEnabled',true);
fprintf('MAIN_SHARED_SRS_DIAGNOSTIC=%s\n',folder);
sixgr.truth.runWaveformLinkBundle(cfg,fullfile(folder,'air_interface'),options);
end
