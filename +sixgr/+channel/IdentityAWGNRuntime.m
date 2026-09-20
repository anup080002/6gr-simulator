classdef IdentityAWGNRuntime
    % Explicit equal-port identity link on the shared physical sample clock.
    % Noise belongs to SharedWaveformPhysicalRuntime, once per receiver.
    % This is a lab channel, not an antenna propagation or fading model.
    methods (Static)
        function tf=enabled(cfg)
            value=sixgr.util.structGet(cfg,'channel.sharedIdentityAWGNEnabled',false);
            assert(islogical(value) && isscalar(value), ...
                'ChannelFactory:InvalidSharedIdentityAWGN', ...
                'channel.sharedIdentityAWGNEnabled must be a scalar logical.');
            tf=value;
            if ~tf, return; end
            assert(upper(string(sixgr.util.structGet(cfg,'channel.model',''))) == "AWGN" && ...
                logical(sixgr.util.structGet(cfg,'channel.awgnOnly',false)) && ...
                ~logical(sixgr.util.structGet(cfg,'channel.pathlossEnabled',false)) && ...
                ~logical(sixgr.util.structGet(cfg,'channel.shadowFadingEnabled',false)), ...
                'ChannelFactory:InvalidSharedIdentityAWGN', ...
                'Shared identity AWGN requires AWGN with pathloss and shadow fading disabled.');
        end

        function tf=isState(state)
            tf=isstruct(state) && isscalar(state) && ...
                string(sixgr.util.structGet(state,'Meta.IdentityOperatorSource',''))== ...
                "explicit_identity_AWGN_shared_sample_operator";
        end

        function contract=physicalContract(cfg)
            % Identity AWGN executes y=x. Geometry/LOS/delay/Doppler values
            % remain useful runtime reporting metadata, but they cannot
            % change that physical operator and may evolve between TDD
            % directions. Keep every operative AWGN/channel field strict.
            assert(sixgr.channel.IdentityAWGNRuntime.enabled(cfg));
            contract=sixgr.util.structGet(cfg,'channel',struct());
            nonoperative=["distance2D_m","distance3D_m", ...
                "propagationDistance2D_m","propagationDistance_m", ...
                "propagationDelay_s","doppler_Hz", ...
                "runtimeSignedDoppler_Hz","losProbability","runtimeLOS"];
            present=intersect(nonoperative,string(fieldnames(contract)),'stable');
            if ~isempty(present), contract=rmfield(contract,cellstr(present)); end
        end

        function state=materialize(state,cfg,txInfo,numTx,numRx)
            assert(sixgr.channel.IdentityAWGNRuntime.enabled(cfg));
            validateattributes(numTx,{'numeric'},{'scalar','integer','finite','positive'});
            validateattributes(numRx,{'numeric'},{'scalar','integer','finite','positive'});
            assert(numTx==numRx,'ChannelFactory:IdentityAWGNPortMismatch', ...
                'Identity AWGN requires equal physical TX/RX dimensions; no port padding, summation or array gain.');
            fs=sixgr.util.structGet(txInfo,'OFDM.SampleRate',NaN);
            validateattributes(fs,{'numeric'},{'scalar','finite','positive'});
            state.Materialized=true; state.UseFading=false; state.Obj=[];
            state.NumTxAnt=double(numTx); state.NumRxAnt=double(numRx);
            state.ExternalLogicalTxPorts=double(numTx);
            state.PhysicalChannelTxElements=double(numTx);
            state.PortToElementMatrix=[]; state.ElementExpansionApplied=false;
            state.SampleRate_Hz=double(fs);
            state.CurrentTime_s=state.CurrentSampleIndex/double(fs);
            state.PendingIdleSamples=0;
            state.ChannelPadSamples=0; state.ChannelTrimSamples=0;
            state.Meta.IdentityOperatorSource="explicit_identity_AWGN_shared_sample_operator";
            state.Meta.ChannelArrayModel="awgn_no_array_channel";
            state.Meta.ChannelObjectSource="sixgr.channel.IdentityAWGNRuntime.materialize";
            state.Meta.ChannelObjectClass="explicit_identity_sample_operator";
            state.Meta.ChannelArrayHandlingStatus="awgn_identity_spatial_dimensions_no_array_kernel";
            state.Meta.ChannelArrayHandlingBlocker="";
            state.Meta.ChannelUsesCountOnlyAntennaModel=false;
            state.Meta.ChannelUsesSameRuntimeAntennaAssumptions=false;
            state.Meta.ChannelGeometryCouplingLevel="not_applicable_no_fading_channel_object";
            state.Meta.ElementPatternChannelApplicability="not_applicable_awgn_identity_channel";
            state.Meta.AntennaChannelConsistencyStatus="classified_not_applicable_runtime_dimensions_validated";
            state.Meta.AntennaChannelConsistencyReason="explicit_identity_awgn_equal_physical_tx_rx_dimensions_no_element_pattern_application";
            state.Meta.TransmitElementPatternApplied=false;
            state.Meta.ReceiveElementPatternApplied=false;
            state.Meta.TransmitElementPatternSource="not_applied_not_applicable_awgn_identity_channel";
            state.Meta.ReceiveElementPatternSource="not_applied_not_applicable_awgn_identity_channel";
            state.Meta.RuntimeTDDReciprocityExact= ...
                sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD";
            state.Meta.RuntimeTDDReciprocityDirection=string(state.Direction);
            state.Meta.RuntimeTDDReciprocitySource="identity_operator_equals_its_nonconjugate_transpose";
            state.Meta.RuntimeTDDReciprocityApproximationMode="none_explicit_identity_lab_channel";
        end

        function reference=reference(state,count)
            assert(sixgr.channel.IdentityAWGNRuntime.isState(state) && ...
                state.Materialized && ~state.UseFading && isempty(state.Obj) && ...
                state.NumTxAnt==state.NumRxAnt, ...
                'ChannelFactory:InvalidIdentityReference','Require the executed identity operator, never a fading replacement.');
            validateattributes(count,{'numeric'},{'scalar','finite','integer','positive'});
            n=state.NumTxAnt;
            % Exact coefficients of y=x, deliberately not labelled NR fading
            % snapshots or receiver channel estimates. Scoring consumers only.
            gains=repmat(reshape(eye(n),[1 1 n n]),[count 1 1 1]);
            reference=struct('Source',"executed_identity_AWGN_operator", ...
                'StartSample',state.CurrentSampleIndex, ...
                'EndSampleExclusive',state.CurrentSampleIndex+count, ...
                'SampleRateHz',state.SampleRate_Hz,'PathGains',gains, ...
                'PathFilters',1, ...
                'SampleTimes_s',(state.CurrentSampleIndex+(0:count-1)')/state.SampleRate_Hz, ...
                'NormalizeChannelOutputs',false,'NormalizePathGains',false, ...
                'NumTransmitAntennas',n,'NumReceiveAntennas',n, ...
                'StateKey',string(state.StateKey),'AdditionalChannelExecutions',0, ...
                'ReceiverEstimatorInput',false,'LargeScaleLossApplied',false, ...
                'PhysicalPortMappingApplied',false,'RFIncluded',false);
        end
    end
end
