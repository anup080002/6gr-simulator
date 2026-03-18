classdef EnergyModelUE
%ENERGYMODELUE UE power/energy model (idle/rx/tx).
%
% Configuration fields (cfg.energy.ue.*):
%   idleW        : idle power (W)
%   rxW          : receive power (W)
%   txWPerWattRF : additional DC power per watt RF output (W/W)
%   sleepW       : deep sleep (W)
%
% Usage:
%   m = sixgr.rf.EnergyModelUE(cfg);
%   p = m.power("tx", txPowerW);
%   eJ = p.totalW * dt_s;

    properties
        IdleW (1,1) double = 1.0
        RxW (1,1) double = 1.5
        TxWPerWattRF (1,1) double = 2.0
        SleepW (1,1) double = 0.1
    end

    methods

        function obj = EnergyModelUE(cfg)
            arguments
                cfg (1,1) struct
            end
            obj.IdleW = double(sixgr.util.structGet(cfg, "energy.ue.idleW", obj.IdleW));
            obj.RxW = double(sixgr.util.structGet(cfg, "energy.ue.rxW", obj.RxW));
            obj.TxWPerWattRF = double(sixgr.util.structGet(cfg, "energy.ue.txWPerWattRF", obj.TxWPerWattRF));
            obj.SleepW = double(sixgr.util.structGet(cfg, "energy.ue.sleepW", obj.SleepW));
        end

        function out = power(obj, state, txPowerW)
            arguments
                obj
                state (1,:) char
                txPowerW (1,1) double = 0
            end

            st = lower(string(state));

            switch st
                case "sleep"
                    p = obj.SleepW;
                case "idle"
                    p = obj.IdleW;
                case "rx"
                    p = obj.RxW;
                case "tx"
                    p = obj.IdleW + obj.TxWPerWattRF * max(txPowerW,0);
                otherwise
                    error("EnergyModelUE:BadState","Unknown state: %s", state);
            end

            out = struct();
            out.totalW = p;
            out.state = char(st);
            out.txPowerW = txPowerW;
        end

    end
end
