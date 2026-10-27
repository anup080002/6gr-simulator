function ok=testPortableCSIBackendConfiguration()
% Full YAML -> builder backend/model authority; no RF or native-private CSI call.
setup6GRSimToolkit('Verbose',false);
p=fullfile('simulator','configs','scenarios','lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(p);cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
authored=s.toStruct();
expected=double(authored.mimo.phase07_strict.rank_domain(:).');
assert(isequal(expected,[1 2 4])&&authored.mimo.phase07_strict.max_rank==4);
policy=sixgr.mimo.resolveRankPolicy(cfg);assert(policy.AdaptiveRank&&~policy.FixedRankAnchor);
assert(string(cfg.phy.csi.selectionBackend)=="portable_typeI_mmse");
assert(~cfg.phy.csi.portableCQIModel.CalibrationQualified&& ...
    numel(cfg.phy.csi.portableCQIModel.ThresholdsDB)==15&& ...
    isequal(cfg.phy.csi.rankDomain,expected)&& ...
    isequal(cfg.phy.csi.reportConfiguration.AllowedRanks,expected)&& ...
    cfg.phy.csi.reportConfiguration.MaxRank==4);
a=s.toStruct();a.csi_acquisition_and_reporting.selection_backend='native_maxse_r2026a';
b=sixgr.lls6g.config.bindCSISelectionBackend(cfg,a);assert(string(b.phy.csi.selectionBackend)=="native_maxse_r2026a");
a.csi_acquisition_and_reporting.selection_backend='portable_typeI_mmse';
a.csi_acquisition_and_reporting.portable_cqi_model.calibration_qualified=true;
reject(@()sixgr.lls6g.config.bindCSISelectionBackend(cfg,a));
a=s.toStruct();a.csi_acquisition_and_reporting.portable_cqi_model.thresholds_db(2)=a.csi_acquisition_and_reporting.portable_cqi_model.thresholds_db(1);
reject(@()sixgr.lls6g.config.bindCSISelectionBackend(cfg,a));
a=s.toStruct();a.csi_acquisition_and_reporting.portable_cqi_model.cqi_table='table2';
reject(@()sixgr.lls6g.config.bindCSISelectionBackend(cfg,a));
% The immediate n40 parent owns the same explicit policy for standalone use.
parent=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
parentCfg=sixgr.lls6g.buildInternalConfig(parent,tempname); parentAuthored=parent.toStruct();
assert(string(parentCfg.phy.csi.selectionBackend)=="portable_typeI_mmse"&& ...
    isequaln(parentCfg.phy.csi.portableCQIModel,cfg.phy.csi.portableCQIModel)&& ...
    isequal(parentCfg.phy.csi.rankDomain,double(parentAuthored.mimo.phase07_strict.rank_domain(:).'))&& ...
    isequal(parentCfg.phy.csi.rankDomain,[1 2 4])&&parentCfg.phy.csi.reportConfiguration.MaxRank==4);
parentPolicy=sixgr.mimo.resolveRankPolicy(parentCfg);assert(parentPolicy.AdaptiveRank&&~parentPolicy.FixedRankAnchor);
assert(isequal(cfg.phy.csi.reportConfiguration.AllowedRanks,parentCfg.phy.csi.reportConfiguration.AllowedRanks));
base=sixgr.config.defaultConfig();assert(string(base.phy.csi.selectionBackend)=="native_maxse_r2026a");
ok=true;
end
function reject(f)
try,f();catch e,assert(strcmp(e.identifier,'sixgr:lls6g:config:InvalidCSISelectionBackend'));return;end
error('test:ExpectedRejection','Missing policy rejection.');
end
