function cfg = TRSConfigStrict(baseCfg, varargin)
%TRSCONFIGSTRICT Build the canonical strict TRS validation config.

cfg = sixgr.phy.trs.buildTRSConfigFromScenario(baseCfg, varargin{:});
end
