classdef RRCTimerSet < handle
    %RRCTIMERSET Separate bounded TS 38.331 procedure timers.

    properties (Access = private)
        Duration
        Expiry
        Running
    end

    methods
        function obj = RRCTimerSet(config)
            arguments
                config struct
            end
            names = ["T300","T301","T304","T310","T311","T319"];
            obj.Duration = containers.Map('KeyType','char','ValueType','double');
            obj.Expiry = containers.Map('KeyType','char','ValueType','double');
            obj.Running = containers.Map('KeyType','char','ValueType','logical');
            for name = names
                if ~isfield(config, name)
                    error("sixgr:rrc:ASN1ConstraintViolation", ...
                        "Timer %s requires an explicit configured duration.", name);
                end
                value = double(config.(name));
                if ~isscalar(value) || ~isfinite(value) || value <= 0
                    error("sixgr:rrc:ASN1ConstraintViolation", ...
                        "Timer %s duration is invalid.", name);
                end
                key = char(name);
                obj.Duration(key) = value;
                obj.Expiry(key) = NaN;
                obj.Running(key) = false;
            end
        end

        function start(obj, name, now)
            key = obj.validate(name);
            if obj.Running(key)
                error("sixgr:rrc:TransactionMismatch", ...
                    "RRC timer %s is already running.", name);
            end
            obj.Running(key) = true;
            obj.Expiry(key) = now + obj.Duration(key);
        end

        function stop(obj, name)
            key = obj.validate(name);
            obj.Running(key) = false;
            obj.Expiry(key) = NaN;
        end

        function tick(obj, now)
            names = string(keys(obj.Running));
            for name = names
                key = char(name);
                if obj.Running(key) && now >= obj.Expiry(key)
                    obj.Running(key) = false;
                    error("sixgr:rrc:ProcedureTimerExpired", ...
                        "RRC procedure timer %s expired at %.6g.", name, now);
                end
            end
        end
    end

    methods (Access = private)
        function key = validate(obj, name)
            key = char(string(name));
            if ~isKey(obj.Duration, key)
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "Unknown RRC timer %s.", string(name));
            end
        end
    end
end
