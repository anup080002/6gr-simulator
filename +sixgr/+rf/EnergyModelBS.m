classdef EnergyModelBS
%ENERGYMODELBS Base station power/energy model (static + load dependent).
%
% This is an engineering model for system-level KPI accounting, not a circuit-level model.
% It is designed to be:
%   - Fast (per TTI/slot updates)
%   - Configurable via cfg.energy.bs.*
%   - Compatible with Hybrid abstraction (PHY BLER LUT -> throughput -> load)
%
% Configuration fields (cfg.energy.bs.*):
%   staticW        : baseline site power (W)
%   perTRxPW       : per-TRxP chain power (W)
%   sleepW         : deep sleep power (W)
%   efficiencyPA   : PA drain efficiency (0..1)
%
% Usage:
%   m = sixgr.rf.EnergyModelBS(cfg);
%   p = m.power("active", nTRxP, load, txPowerW);
%   eJ = p.totalW * dt_s;
%
% Keep ASCII only.

    properties
        StaticW (1,1) double = 200
        PerTRxPW (1,1) double = 10
        SleepW (1,1) double = 20
        EfficiencyPA (1,1) double = 0.35
    end

    methods

        function obj = EnergyModelBS(cfg)
            arguments
                cfg (1,1) struct
            end
            obj.StaticW = double(sixgr.util.structGet(cfg, "energy.bs.staticW", obj.StaticW));
            obj.PerTRxPW = double(sixgr.util.structGet(cfg, "energy.bs.perTRxPW", obj.PerTRxPW));
            obj.SleepW = double(sixgr.util.structGet(cfg, "energy.bs.sleepW", obj.SleepW));
            obj.EfficiencyPA = double(sixgr.util.structGet(cfg, "energy.bs.efficiencyPA", obj.EfficiencyPA));
            obj.EfficiencyPA = min(max(obj.EfficiencyPA, 1e-3), 1.0);
        end

        function out = power(obj, state, nTRxP, load, txPowerW)
            %POWER Compute instantaneous power breakdown.
            arguments
                obj
                state (1,:) char
                nTRxP (1,1) double {mustBeNonnegative} = 1
                load (1,1) double = 0
                txPowerW (1,1) double = 0
            end

            st = lower(string(state));
            load = min(max(load,0),1);

            if st == "sleep"
                out = struct("totalW", obj.SleepW, ...
                             "staticW", 0, ...
                             "trxW", 0, ...
                             "paW", 0, ...
                             "load", load, ...
                             "state", char(st));
                return;
            end

            pStatic = obj.StaticW;
            pTRx = obj.PerTRxPW * nTRxP * (0.2 + 0.8*load); % small idle floor
            pPA = 0;
            if txPowerW > 0
                pPA = txPowerW / obj.EfficiencyPA;
            end

            out = struct();
            out.totalW = pStatic + pTRx + pPA;
            out.staticW = pStatic;
            out.trxW = pTRx;
            out.paW = pPA;
            out.load = load;
            out.state = char(st);
            out.nTRxP = nTRxP;
            out.txPowerW = txPowerW;
        end

    end
end
