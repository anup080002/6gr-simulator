function cfg = buildSRSConfigFromRRC(baseCfg, varargin)
%BUILDSRSCONFIGFROMRRC Resolve strict SRS config from the repo RRC surface.
%
% The current repo carries SRS RRC fields through resolved scenario structs.
% This wrapper preserves the binding-source provenance instead of silently
% inventing a second parser.

cfg = sixgr.phy.srs.buildSRSConfigFromScenario(baseCfg, varargin{:});
cfg.BindingSource = "rrc_srs_resource_set";
cfg.ConfigHash = sixgr.phy.srs.hashSRSConfig(cfg);
cfg.StrictValidation = sixgr.phy.srs.validateSRSConfigStrict(cfg);
end
