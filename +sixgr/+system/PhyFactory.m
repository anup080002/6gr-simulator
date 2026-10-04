classdef PhyFactory
% sixgr.system.PhyFactory
% Build system-level PHY backend from config/params.

    methods(Static)
        function cfg = resolveConfig(cfg, params)
            % Internal runner overrides must reach scheduler and PHY alike.
            % This does not install calibration or enable modeled feedback.
            if nargin < 2, params = struct(); end
            backend = lower(string(sixgr.util.structGet(params, "PHYBackend", ...
                sixgr.util.structGet(cfg, "system.phyBackend", "waveform"))));
            if ~isscalar(backend) || ismissing(backend) || ...
                    ~any(backend == ["waveform","calibrated_link_abstraction"])
                if isscalar(backend) && ~ismissing(backend) && ...
                        any(backend == ["abstract","lut","bler_lut","bler_db","proxy","lls_calibrated_link2system"])
                    error("sixgr:system:ProxyBackendRemoved", ...
                        "System PHY backend '%s' was removed. Use waveform or explicitly calibrated_link_abstraction.", backend);
                end
                error("sixgr:system:UnsupportedPHYBackend", ...
                    "system.phyBackend / PHYBackend must select waveform or calibrated_link_abstraction.");
            end
            cfg.system.phyBackend = char(backend);
        end

        function phy = create(cfg, params, varargin)
            if nargin < 2 || isempty(params)
                params = struct();
            end
            cfg = sixgr.system.PhyFactory.resolveConfig(cfg,params);
            seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 31;
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    k = lower(char(string(varargin{i})));
                    if strcmp(k, "seed")
                        seed = double(varargin{i+1});
                    end
                end
            end

            phyBackend = cfg.system.phyBackend;
            if strcmp(phyBackend, "waveform")
                strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
                phy = sixgr.system.WaveformPHY(cfg, params, "Seed", seed, "StrictMode", strictMode);
                return;
            end
            if strcmp(phyBackend, "calibrated_link_abstraction")
                phy=sixgr.system.CalibratedLinkPHY(cfg,params,seed);
                return;
            end
        end
    end
end
