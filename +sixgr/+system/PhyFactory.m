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

            strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
            db = sixgr.util.structGet(params, "BLERDB", struct());
            lut = sixgr.util.structGet(params, "BLERLUT", []);
            if ~isstruct(db)
                db = struct();
            end

            if ~isempty(fieldnames(db))
                dbN = sixgr.system.BLER_DB(db);
                if strictMode
                    dbSrc = lower(string(sixgr.util.structGet(dbN, "Source", "")));
                    if contains(dbSrc, "default") || contains(dbSrc, "synthetic")
                        error("sixgr:system:PhyFactory:StrictSyntheticDB", ...
                            "Strict mode requires calibrated BLERDB (received source: %s).", dbSrc);
                    end
                end
                payload = struct("DB", dbN, "StrictMode", strictMode);
            elseif ~isempty(lut)
                lutN = sixgr.system.BLER_LUT(lut);
                if strictMode
                    lutSrc = lower(string(sixgr.util.structGet(lutN, "Source", "")));
                    if contains(lutSrc, "default") || contains(lutSrc, "synthetic")
                        error("sixgr:system:PhyFactory:StrictSyntheticLUT", ...
                            "Strict mode requires calibrated BLERLUT (received source: %s).", lutSrc);
                    end
                end
                payload = struct("LUT", lutN, "StrictMode", strictMode);
            else
                if strictMode
                    error("sixgr:system:PhyFactory:MissingCalibration", ...
                        "Strict mode requires BLERDB or BLERLUT calibration.");
                end
                payload = struct("LUT", sixgr.system.BLER_LUT(), "StrictMode", strictMode);
            end

            phy = sixgr.system.AbstractPHY(payload, "Seed", seed);
        end
    end
end
