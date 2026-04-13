classdef PhyFactory
% sixgr.system.PhyFactory
% Build system-level PHY backend from config/params.

    methods(Static)
        function phy = create(cfg, params, varargin)
            if nargin < 2 || isempty(params)
                params = struct();
            end
            seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 31;
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    k = lower(char(string(varargin{i})));
                    if strcmp(k, "seed")
                        seed = double(varargin{i+1});
                    end
                end
            end

            phyBackend = lower(char(string(sixgr.util.structGet(params, "PHYBackend", ...
                sixgr.util.structGet(cfg, "system.phyBackend", "waveform")))));
            if strcmp(phyBackend, "waveform")
                strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
                phy = sixgr.system.WaveformPHY(cfg, params, "Seed", seed, "StrictMode", strictMode);
                return;
            end
            error("sixgr:system:ProxyBackendRemoved", "%s", ...
                sprintf("System PHY backend '%s' has been removed from the active simulator. Use system.phyBackend='waveform' only.", phyBackend));
        end
    end
end
