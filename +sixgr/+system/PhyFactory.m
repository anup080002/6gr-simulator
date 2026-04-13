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
            if any(string(phyBackend) == ["abstract","lut","bler_lut","bler_db","proxy","lls_calibrated_link2system"])
                error("sixgr:system:ProxyBackendRemoved", ...
                    "System PHY backend '%s' was removed from active runtime. Use system.phyBackend='waveform' so grants are decoded through WaveformPHY.", phyBackend);
            end
            error("sixgr:system:UnsupportedPHYBackend", ...
                "Unsupported system PHY backend '%s'. Use 'waveform'.", phyBackend);
        end
    end
end
