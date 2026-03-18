classdef AbstractPHY < handle
% sixgr.system.AbstractPHY
% Abstract PHY mapping SINR -> BLER and decode success.

    properties
        LUT struct
        DB struct
        StrictMode (1,1) logical = false
        Stream
    end

    methods
        function obj = AbstractPHY(lut, varargin)
            if nargin < 1 || isempty(lut)
                lut = struct("LUT", sixgr.system.BLER_LUT());
            end
            obj.LUT = struct();
            obj.DB = struct();

            if isstruct(lut) && isfield(lut, "DB")
                obj.DB = sixgr.system.BLER_DB(lut.DB);
                if isfield(lut, "LUT") && ~isempty(lut.LUT)
                    obj.LUT = sixgr.system.BLER_LUT(lut.LUT);
                elseif ~isempty(fieldnames(obj.DB))
                    % Build a representative LUT slice for compatibility.
                    snr = obj.DB.Axes.SNR_dB(:);
                    b = NaN(size(snr));
                    for i = 1:numel(snr)
                        ctx = struct("Direction", "DL", "SINR_dB", snr(i));
                        b(i) = sixgr.system.BLER_DB("query", obj.DB, ctx, false);
                    end
                    obj.LUT = sixgr.system.BLER_LUT("SNR_dB", snr, "BLER", b);
                end
                obj.StrictMode = logical(sixgr.util.structGet(lut, "StrictMode", false));
            elseif isstruct(lut) && isfield(lut, "LUT")
                obj.LUT = sixgr.system.BLER_LUT(lut.LUT);
                obj.StrictMode = logical(sixgr.util.structGet(lut, "StrictMode", false));
            else
                obj.LUT = sixgr.system.BLER_LUT(lut);
            end

            seed = [];
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    key = lower(char(string(varargin{i})));
                    val = varargin{i+1};
                    if strcmp(key, "seed")
                        seed = double(val);
                    elseif strcmp(key, "strictmode")
                        obj.StrictMode = logical(val);
                    end
                end
            end

            if isempty(seed)
                obj.Stream = RandStream("mt19937ar","Seed",1);
            else
                obj.Stream = RandStream("mt19937ar","Seed",seed);
            end

            if obj.StrictMode
                if ~isempty(fieldnames(obj.DB))
                    src = lower(string(sixgr.util.structGet(obj.DB, "Source", "")));
                    if contains(src, "default") || contains(src, "synthetic")
                        error("sixgr:system:AbstractPHY:StrictSyntheticDB", ...
                            "Strict mode forbids synthetic/default BLER DB source: %s", src);
                    end
                elseif ~isempty(fieldnames(obj.LUT))
                    src = lower(string(sixgr.util.structGet(obj.LUT, "Source", "")));
                    if contains(src, "default") || contains(src, "synthetic")
                        error("sixgr:system:AbstractPHY:StrictSyntheticLUT", ...
                            "Strict mode forbids synthetic/default BLER LUT source: %s", src);
                    end
                end
            end
        end

        function bler = mapBLER(obj, in)
            if isstruct(in)
                ctx = in;
                if ~isempty(fieldnames(obj.DB))
                    bler = sixgr.system.BLER_DB("query", obj.DB, ctx, obj.StrictMode);
                    return;
                end

                sinr_dB = double(sixgr.util.structGet(ctx, "SINR_dB", NaN));
                x = obj.LUT.SNR_dB(:);
                y = obj.LUT.BLER(:);
                bler = interp1(x, y, sinr_dB, "linear", "extrap");
                bler = max(1e-4, min(0.9999, bler));

                if obj.StrictMode
                    return;
                end

                cqi = double(sixgr.util.structGet(ctx, "CQI", 10));
                prb = double(sixgr.util.structGet(ctx, "PRBCount", 50));
                layers = double(sixgr.util.structGet(ctx, "NumLayers", 1));
                tcr = double(sixgr.util.structGet(ctx, "TargetCodeRate", 0.5));
                dop = double(sixgr.util.structGet(ctx, "DopplerHz", 0));
                scs = double(sixgr.util.structGet(ctx, "SCS_kHz", 30));
                dir = upper(string(sixgr.util.structGet(ctx, "Direction", "DL")));

                eff = 0;
                eff = eff - 0.020 * (cqi - 9);
                eff = eff + 0.0008 * (prb - 50);
                eff = eff + 0.030 * (layers - 1);
                eff = eff + 0.75 * (tcr - 0.5);
                eff = eff + 0.0012 * dop;
                eff = eff + 0.002 * max(scs - 30, 0);
                if dir == "UL"
                    eff = eff + 0.03;
                end
                bler = bler + eff;
                bler = max(1e-4, min(0.9999, bler));
                return;
            end

            sinr_dB = double(in);
            x = obj.LUT.SNR_dB(:);
            y = obj.LUT.BLER(:);
            bler = interp1(x, y, sinr_dB, "linear", "extrap");
            bler = max(1e-4, min(0.9999, bler));
        end

        function [ok, bler] = decode(obj, in)
            bler = obj.mapBLER(in);
            u = rand(obj.Stream, size(bler));
            ok = (u > bler);
        end
    end
end
