function strictCfg = PDCCHConfigStrict(baseCfg, varargin)
%PDCCHCONFIGSTRICT Public strict PDCCH configuration entry point.

strictCfg = sixgr.phy.pdcch.buildPDCCHConfigFromScenario(baseCfg, varargin{:});
end
