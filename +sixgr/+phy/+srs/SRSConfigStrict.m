function cfg = SRSConfigStrict(baseCfg, varargin)
%SRSCONFIGSTRICT Build the canonical strict SRS validation config.

cfg = sixgr.phy.srs.buildSRSConfigFromScenario(baseCfg, varargin{:});
end
