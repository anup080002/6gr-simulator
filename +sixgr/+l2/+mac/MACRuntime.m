classdef MACRuntime < handle
    %MACRUNTIME Canonical event-sourced Phase-08 production runtime.
    properties (SetAccess=private)
        Config (1,1) struct
        EventStore (1,1) sixgr.l2.mac.MACEventStore
        Lineage (1,1) sixgr.l2.mac.PacketLineageGraph
        ConfigurationEpoch (1,1) sixgr.l2.mac.MACConfigurationEpoch
    end
    methods
        function obj=MACRuntime(config)
            arguments
                config (1,1) struct
            end
            sixgr.l2.mac.MACRuntime.validateConfig(config);
            obj.Config=config;
            obj.EventStore=sixgr.l2.mac.MACEventStore();
            obj.Lineage=sixgr.l2.mac.PacketLineageGraph();
            obj.ConfigurationEpoch=sixgr.l2.mac.MACConfigurationEpoch( ...
                config.configuration_epoch,config);
            obj.EventStore.append(sixgr.l2.mac.MACEvent( ...
                sixgr.l2.mac.MACEventType.CONFIGURATION_EPOCH, ...
                "ConfigurationEpoch",config.configuration_epoch, ...
                "Payload",struct("Digest",obj.ConfigurationEpoch.Digest)));
        end
    end
    methods (Static)
        function validateConfig(config)
            required=["profile_id","configuration_epoch","harq", ...
                "timing","scheduler","bsr","phr","sr","lcp", ...
                "pdu","timing_advance"];
            for field=required
                if ~isfield(config,field)
                    error("sixgr:mac:MissingConfiguration", ...
                        "MAC configuration requires %s.",field);
                end
            end
            resolved=sixgr.l2.mac.MACCapabilityProfile.resolve(config.profile_id);
            if ~resolved.Supported
                error("sixgr:mac:UnsupportedCapabilityProfile", ...
                    "MAC profile %s is unsupported.",config.profile_id);
            end
            if ~isfield(config.harq,"rv_sequence") || ...
                    isempty(config.harq.rv_sequence)
                error("sixgr:mac:MissingConfiguration", ...
                    "HARQ RV sequence must be explicit.");
            end
            for field=["k0","k1","k2","tdd_pattern"]
                if ~isfield(config.timing,field)
                    error("sixgr:mac:MissingConfiguration", ...
                        "MAC timing requires %s.",field);
                end
            end
        end
    end
end
