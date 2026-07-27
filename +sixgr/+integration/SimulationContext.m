classdef SimulationContext
    %SIMULATIONCONTEXT Single immutable dependency context for a run.
    properties (SetAccess=immutable)
        Configuration
        Clock
        Registry
        Scheduler
        StateStore
        Resources
        Measurements
        SeedLedger
    end
    methods (Static)
        function obj = create(configuration,seedList)
            if nargin < 2, seedList = 11; end
            configuration.verifyExecuted();
            resolved = configuration.ResolvedStruct;
            sampleRate = double(sixgr.util.structGet(resolved, ...
                "waveform.sample_rate_hz",30.72e6));
            nfft = double(sixgr.util.structGet(resolved, ...
                "waveform.fft_size",1024));
            symbols = 14;
            slots = 10*2^round(log2(double(sixgr.util.structGet( ...
                resolved,"waveform.scs_khz",15))/15));
            clock = sixgr.integration.AbsoluteRadioClock( ...
                sampleRate,nfft,symbols,slots);
            registry = sixgr.integration.ComponentRegistry(configuration.RunID);
            registry.register("AbsoluteRadioClock", ...
                "sixgr.integration.AbsoluteRadioClock");
            registry.register("ResourceTransactionManager", ...
                "sixgr.integration.ResourceTransactionManager");
            registry.register("CanonicalWaveformEngine", ...
                "sixgr.phy.waveform.CanonicalOFDMModulator");
            registry.register("ChannelApplicationContract", ...
                "sixgr.integration.ChannelApplicationContract");
            registry.register("RFFrontEndRuntime","sixgr.rf.runtime.RFChain");
            registry.register("CommonReceiverPipeline", ...
                "sixgr.integration.CommonReceiverPipeline");
            registry.register("EventSourcedStateStore", ...
                "sixgr.integration.EventSourcedStateStore");
            registry.register("AbsoluteEventScheduler", ...
                "sixgr.integration.AbsoluteEventScheduler");
            registry.register("PacketLineageBridge", ...
                "sixgr.integration.PacketLineageBridge");
            registry.register("IntegrationArtifactExporter", ...
                "sixgr.integration.IntegrationArtifactExporter");
            scheduler = sixgr.integration.AbsoluteEventScheduler(clock);
            store = sixgr.integration.EventSourcedStateStore(configuration.RunID);
            resources = sixgr.integration.ResourceTransactionManager( ...
                configuration.RunID,configuration.ConfigurationEpoch);
            measurements = sixgr.integration.MeasurementAvailabilityQueue( ...
                scheduler,store,configuration.ConfigurationEpoch);
            seedList = double(seedList(:));
            taskID = compose("TASK-%04d",(1:numel(seedList)).');
            seedLedger = table(repmat(configuration.RunID,numel(seedList),1), ...
                taskID,seedList,'VariableNames',{'RunID','TaskID','Seed'});
            obj = sixgr.integration.SimulationContext(configuration,clock, ...
                registry,scheduler,store,resources,measurements,seedLedger);
        end
    end
    methods (Access=private)
        function obj = SimulationContext(configuration,clock,registry, ...
                scheduler,store,resources,measurements,seedLedger)
            obj.Configuration = configuration; obj.Clock = clock;
            obj.Registry = registry; obj.Scheduler = scheduler;
            obj.StateStore = store; obj.Resources = resources;
            obj.Measurements = measurements; obj.SeedLedger = seedLedger;
        end
    end
end
