classdef IdentityAWGNRuntime
    % Explicit identity or configured rectangular AWGN spatial operator.
    % Noise belongs to SharedWaveformPhysicalRuntime, once per receiver.
    % This is a lab channel, not an antenna propagation or fading model.
    methods (Static)
        function tf=enabled(cfg)
            value=sixgr.util.structGet(cfg,'channel.sharedIdentityAWGNEnabled',false);
            assert(islogical(value) && isscalar(value), ...
                'ChannelFactory:InvalidSharedIdentityAWGN', ...
                'channel.sharedIdentityAWGNEnabled must be a scalar logical.');
            matrix=sixgr.util.structGet(cfg,'channel.awgnSpatialMatrixDL',[]);
            if ~isempty(matrix)
                validateattributes(matrix,{'numeric'},{'2d','nonempty','finite'});
                assert(~value,'ChannelFactory:ConflictingAWGNOperators', ...
                    'Explicit spatial matrix and identity AWGN are mutually exclusive.');
            end
            tf=value || ~isempty(matrix);
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
                any(string(sixgr.util.structGet(state,'Meta.IdentityOperatorSource',''))== ...
                ["explicit_identity_AWGN_shared_sample_operator", ...
                 "explicit_matrix_AWGN_shared_sample_operator"]);
        end

        function contract=physicalContract(cfg)
            % Execute y=x for identity, or y=x*H.' for a configured matrix.
            % Geometry/LOS/delay/Doppler values
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
            matrix=sixgr.util.structGet(cfg,'channel.awgnSpatialMatrixDL',[]);
            fixedMatrix=~isempty(matrix);
            if fixedMatrix
                if string(state.Direction)=="UL", matrix=matrix.'; end
                assert(isequal(size(matrix),[numRx numTx]), ...
                    'ChannelFactory:AWGNMatrixPortMismatch', ...
                    'Executed AWGN matrix must match receive-by-transmit physical dimensions.');
            else
                assert(numTx==numRx,'ChannelFactory:IdentityAWGNPortMismatch', ...
                    'Identity AWGN requires equal physical TX/RX dimensions; no port padding, summation or array gain.');
                matrix=eye(numRx,numTx);
            end
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
            state.Meta.AWGNSpatialMatrix=matrix;
            if fixedMatrix
                state.Meta.IdentityOperatorSource="explicit_matrix_AWGN_shared_sample_operator";
                state.Meta.ChannelObjectClass="explicit_fixed_matrix_sample_operator";
                state.Meta.ChannelArrayHandlingStatus="awgn_configured_spatial_matrix_no_array_kernel";
                state.Meta.ElementPatternChannelApplicability="not_applicable_awgn_fixed_matrix_channel";
                state.Meta.AntennaChannelConsistencyReason="explicit_configured_rx_by_tx_matrix_no_element_patterns";
                state.Meta.TransmitElementPatternSource="not_applied_awgn_fixed_matrix_channel";
                state.Meta.ReceiveElementPatternSource="not_applied_awgn_fixed_matrix_channel";
                state.Meta.RuntimeTDDReciprocitySource="configured_DL_matrix_UL_nonconjugate_transpose";
                state.Meta.RuntimeTDDReciprocityApproximationMode="none_explicit_fixed_matrix_lab_channel";
            end
        end

        function reference=reference(state,count)
            assert(sixgr.channel.IdentityAWGNRuntime.isState(state) && ...
                state.Materialized && ~state.UseFading && isempty(state.Obj), ...
                'ChannelFactory:InvalidIdentityReference','Require the executed identity operator, never a fading replacement.');
            validateattributes(count,{'numeric'},{'scalar','finite','integer','positive'});
            n=state.NumTxAnt; nr=state.NumRxAnt;
            % Exact coefficients of the executed linear spatial operator,
            % deliberately not labelled NR fading
            % snapshots or receiver channel estimates. Scoring consumers only.
            matrix=state.Meta.AWGNSpatialMatrix;
            gains=repmat(reshape(matrix.',[1 1 n nr]),[count 1 1 1]);
            reference=struct('Source',"executed_identity_AWGN_operator", ...
                'StartSample',state.CurrentSampleIndex, ...
                'EndSampleExclusive',state.CurrentSampleIndex+count, ...
                'SampleRateHz',state.SampleRate_Hz,'PathGains',gains, ...
                'PathFilters',1, ...
                'SampleTimes_s',(state.CurrentSampleIndex+(0:count-1)')/state.SampleRate_Hz, ...
                'NormalizeChannelOutputs',false,'NormalizePathGains',false, ...
                'NumTransmitAntennas',n,'NumReceiveAntennas',nr, ...
                'StateKey',string(state.StateKey),'AdditionalChannelExecutions',0, ...
                'ReceiverEstimatorInput',false,'LargeScaleLossApplied',false, ...
                'PhysicalPortMappingApplied',false,'RFIncluded',false);
            if state.Meta.IdentityOperatorSource=="explicit_matrix_AWGN_shared_sample_operator"
                reference.Source="executed_fixed_matrix_AWGN_operator";
                reference.SpatialMatrix=matrix;
            end
        end
    end
end
