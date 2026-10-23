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
%   efficiencyPA   : PA drain efficiency (0 < efficiencyPA <= 1)
%   idleRFChainPowerFraction : awake chain floor relative to full load (0..1)
% P = staticW + perTRxPW*nTRxP*(fIdle+(1-fIdle)*load) + txPowerW/efficiencyPA.
% This equation and its parameters are engineering assumptions, not 3GPP
% hardware requirements. Strict LLS callers resolve every operand from YAML.
%
% Usage:
%   m = sixgr.rf.EnergyModelBS(cfg);
%   p = m.power("active", nTRxP, load, txPowerW);
%   eJ = p.totalW * dt_s;
%
% Keep ASCII only.

    properties
        StaticW (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 200
        PerTRxPW (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 10
        SleepW (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 20
        EfficiencyPA (1,1) double {mustBeReal,mustBeFinite,mustBePositive,mustBeLessThanOrEqual(EfficiencyPA,1)} = 0.35
        IdleRFChainPowerFraction (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative,mustBeLessThanOrEqual(IdleRFChainPowerFraction,1)} = 0.2
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
            obj.IdleRFChainPowerFraction = double(sixgr.util.structGet(cfg, ...
                "energy.bs.idleRFChainPowerFraction", obj.IdleRFChainPowerFraction));
        end

        function out = power(obj, state, nTRxP, load, txPowerW)
            %POWER Compute instantaneous power breakdown.
            arguments
                obj
                state (1,:) char
                nTRxP (1,1) double {mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative} = 1
                load (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative,mustBeLessThanOrEqual(load,1)} = 0
                txPowerW (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 0
            end

            st = lower(string(state));
            assert(any(st==["active","idle","sleep"]), ...
                'sixgr:rf:InvalidBSEnergyState','Use active, idle or sleep.');
            assert(nTRxP>0 || txPowerW==0, ...
                'sixgr:rf:InvalidBSEnergyTransmission','Positive RF output requires a transmitting RF chain.');
            assert(st=="active" || (load==0 && txPowerW==0), ...
                'sixgr:rf:InvalidBSEnergyState','Idle/sleep states cannot include active load or RF output power.');

            if st == "sleep"
                out = struct("totalW", obj.SleepW, ...
                             "staticW", 0, ...
                             "trxW", 0, ...
                             "paW", 0, ...
                             "idleRFChainPowerFraction", obj.IdleRFChainPowerFraction, ...
                             "load", load, ...
                             "state", char(st));
                return;
            end

            pStatic = obj.StaticW;
            fIdle = obj.IdleRFChainPowerFraction;
            pTRx = obj.PerTRxPW * nTRxP * (fIdle + (1-fIdle)*load);
            pPA = 0;
            if txPowerW > 0
                pPA = txPowerW / obj.EfficiencyPA;
            end

            out = struct();
            out.totalW = pStatic + pTRx + pPA;
            assert(isfinite(out.totalW),'sixgr:rf:EnergyModelOverflow', ...
                'Declared power operands exceed finite model arithmetic.');
            out.staticW = pStatic;
            out.trxW = pTRx;
            out.paW = pPA;
            out.load = load;
            out.state = char(st);
            out.nTRxP = nTRxP;
            out.txPowerW = txPowerW;
            out.idleRFChainPowerFraction = fIdle;
        end

    end
end
