classdef SLSAbstractionFixtureProvider < sixgr.system.abstraction.SpatialGrantProvider
    % Numerical fixture only. Never use this class for study results.
    properties
        SINR_dB double = 0
        Calls double = 0
        LastContext struct = struct()
        LastObservation struct = struct()
        FeedbackConfig struct = struct()
    end
    methods
        function obj=SLSAbstractionFixtureProvider(varargin) %#ok<INUSD>
        end
        function observations=observeSRS(obj,state)
            cfg=obj.FeedbackConfig;
            assert(~isempty(fieldnames(cfg)),'test:MissingFeedbackFixture','Explicit fixture configuration required.');
            arch=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'ue','Signal','PUSCH','MinimumPorts',1);
            nt=double(arch.NumPorts);
            observations=struct('ObservationID',"test_srs_"+state.AbsoluteSlot0, ...
                'ExecutionID',string(cfg.run.executionID),'ChannelOwnerID',"test_only_identity", ...
                'UEIndex',1,'ServingCell',state.ServingCells(1), ...
                'SourceAbsoluteSlot0',state.AbsoluteSlot0,'AvailableAbsoluteSlot0',state.AbsoluteSlot0+1, ...
                'SRI',0,'ChannelEstimate',eye(nt),'ExternalCovariance',eye(nt), ...
                'TotalPUSCHPower',1,'ReceiverType',"lmmse",'RFProfileID',"test_ideal", ...
                'EstimationAssumption',"ideal_delayed_channel_estimate", ...
                'SourceClassification',"modeled_srs_not_waveform_measurement");
        end
        function o=evaluate(obj,ctx,slotContext)
            assert(ctx.TTI==slotContext.TTI);
            obj.LastContext=ctx;
            obj.Calls=obj.Calls+1;
            n=ctx.NumLayers;
            o=struct('Channel',eye(n),'Precoder',eye(n)/sqrt(n), ...
                'TotalTransmitPower',n*10^(obj.SINR_dB/10),'ExternalCovariance',eye(n), ...
                'RFProfileID',"test_ideal",'ReceiverProfileID',"test_lmmse", ...
                'ChannelProfileID',"test_identity_awgn_no_delay_no_doppler", ...
                'ModelObservationID',"fixture_"+string(ctx.TTI), ...
                'SourceClassification',"modeled_spatial_channel_not_waveform_measurement");
            if ~isempty(fieldnames(obj.FeedbackConfig)) && isfield(ctx.Grant,'ModeledSRSFeedback')
                r=ctx.Grant.ModeledSRSFeedback;
                o.Channel=eye(r.NumPorts); o.Precoder=r.MatrixPorts;
                o.ExternalCovariance=eye(r.NumPorts);
            end
            obj.LastObservation=o;
        end
    end
end
