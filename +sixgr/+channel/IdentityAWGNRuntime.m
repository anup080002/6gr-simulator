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
            state.PhysicalChannelTxElements=double(numTx);
            priorMap=sixgr.util.structGet(state,'PortToElementMatrix',[]);
            priorExpansion=logical(sixgr.util.structGet( ...
                state,'ElementExpansionApplied',false));
            if priorExpansion
                assert(isnumeric(priorMap) && ismatrix(priorMap) && ...
                    size(priorMap,1)==numTx && ...
                    norm(priorMap'*priorMap-eye(size(priorMap,2)),'fro')<= ...
                    1e-9*max(1,size(priorMap,2)), ...
                    'ChannelFactory:InvalidIdentityAWGNPortProjection', ...
                    ['The explicit AWGN operator requires the retained ' ...
                     'logical-port projection to be dimensionally valid and unit norm.']);
                state.ExternalLogicalTxPorts=double(size(priorMap,2));
                state.PortToElementMatrix=priorMap;
                state.ElementExpansionApplied=true;
            else
                state.ExternalLogicalTxPorts=double(numTx);
                state.PortToElementMatrix=[];
                state.ElementExpansionApplied=false;
            end
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
            state.Meta.AWGNSpatialMatrixBaseline=matrix;
            state.Meta.BeamFailureRecoveryEpisodeEnabled=logical( ...
                sixgr.util.structGet(cfg,'channel.awgnBeamFailureRecoveryEnabled',false));
            state.Meta.BeamFailureStartSlot=double(sixgr.util.structGet( ...
                cfg,'channel.awgnBeamFailureStartSlot',NaN));
            state.Meta.BeamFailureEndSlotExclusive=double(sixgr.util.structGet( ...
                cfg,'channel.awgnBeamFailureEndSlotExclusive',NaN));
            episodeMatrix=sixgr.util.structGet(cfg,'channel.awgnBeamFailureMatrixDL',[]);
            if ~isempty(episodeMatrix) && string(state.Direction)=="UL"
                episodeMatrix=episodeMatrix.';
            end
            state.Meta.BeamFailureSpatialMatrix=episodeMatrix;
            if state.Meta.BeamFailureRecoveryEpisodeEnabled
                carrier=sixgr.phy.grid.makeCarrier(cfg);
                state.Meta.BeamFailureStartSample=double( ...
                    sixgr.phy.frame.slotStartSample(carrier, ...
                    state.Meta.BeamFailureStartSlot,state.SampleRate_Hz));
                state.Meta.BeamFailureEndSampleExclusive=double( ...
                    sixgr.phy.frame.slotStartSample(carrier, ...
                    state.Meta.BeamFailureEndSlotExclusive,state.SampleRate_Hz));
            end
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

        function segments=matrixSegmentsForInterval(state,count)
            % Return at most three exact, non-overlapping sample ranges.
            % A caller is allowed to submit a waveform spanning either
            % episode boundary; the physical operator changes at the exact
            % configured sample rather than depending on call chunking.
            validateattributes(count,{'numeric'},{'scalar','finite','integer','positive'});
            baseline=state.Meta.AWGNSpatialMatrix;
            segments=struct('FirstOffset',0,'EndOffsetExclusive',double(count), ...
                'Matrix',baseline,'EpisodeActive',false);
            if ~logical(sixgr.util.structGet(state, ...
                    'Meta.BeamFailureRecoveryEpisodeEnabled',false))
                return;
            end
            episode=sixgr.util.structGet(state,'Meta.BeamFailureSpatialMatrix',[]);
            assert(~isempty(episode) && isequal(size(episode),size(baseline)), ...
                'ChannelFactory:InvalidAWGNBeamFailureMatrix', ...
                'The physical beam-failure matrix must match the active channel direction.');
            absoluteStart=double(state.CurrentSampleIndex);
            absoluteEnd=absoluteStart+double(count);
            failureStart=double(state.Meta.BeamFailureStartSample);
            failureEnd=double(state.Meta.BeamFailureEndSampleExclusive);
            activeStart=max(absoluteStart,failureStart);
            activeEnd=min(absoluteEnd,failureEnd);
            if activeStart>=activeEnd
                return;
            end
            segments=repmat(segments,0,1);
            if absoluteStart<activeStart
                segments(end+1,1)=struct('FirstOffset',0, ... %#ok<AGROW>
                    'EndOffsetExclusive',activeStart-absoluteStart, ...
                    'Matrix',baseline,'EpisodeActive',false);
            end
            segments(end+1,1)=struct( ... %#ok<AGROW>
                'FirstOffset',activeStart-absoluteStart, ...
                'EndOffsetExclusive',activeEnd-absoluteStart, ...
                'Matrix',episode,'EpisodeActive',true);
            if activeEnd<absoluteEnd
                segments(end+1,1)=struct( ... %#ok<AGROW>
                    'FirstOffset',activeEnd-absoluteStart, ...
                    'EndOffsetExclusive',double(count), ...
                    'Matrix',baseline,'EpisodeActive',false);
            end
            assert(segments(1).FirstOffset==0 && ...
                segments(end).EndOffsetExclusive==double(count) && ...
                all([segments.EndOffsetExclusive]>[segments.FirstOffset]), ...
                'ChannelFactory:InvalidAWGNBeamFailureSegmentation', ...
                'Beam-failure sample-domain segmentation must cover the input exactly once.');
        end

        function [y,episodeActive,segments]=applyInterval(state,x)
            assert(isnumeric(x) && ismatrix(x) && ~isempty(x) && ...
                size(x,2)==state.NumTxAnt && all(isfinite(x(:))), ...
                'ChannelFactory:InvalidIdentityAWGNInput', ...
                'The AWGN spatial operator requires finite samples on every transmit dimension.');
            segments=sixgr.channel.IdentityAWGNRuntime.matrixSegmentsForInterval( ...
                state,size(x,1));
            y=zeros(size(x,1),state.NumRxAnt,'like',x);
            for k=1:numel(segments)
                idx=(segments(k).FirstOffset+1):segments(k).EndOffsetExclusive;
                y(idx,:)=x(idx,:)*segments(k).Matrix.';
            end
            episodeActive=any([segments.EpisodeActive]);
        end

        function [matrix,episodeActive]=matrixForInterval(state,count)
            % Compatibility helper for callers that require one matrix.
            % Mixed intervals must use applyInterval so their physical
            % sample-domain transition cannot be collapsed or mislabeled.
            segments=sixgr.channel.IdentityAWGNRuntime.matrixSegmentsForInterval( ...
                state,count);
            assert(numel(segments)==1, ...
                'ChannelFactory:AWGNBeamFailureMixedIntervalRequiresPiecewiseApply', ...
                'A mixed beam-failure interval requires piecewise sample-domain application.');
            matrix=segments.Matrix;
            episodeActive=logical(segments.EpisodeActive);
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
            segments=sixgr.channel.IdentityAWGNRuntime.matrixSegmentsForInterval( ...
                state,count);
            gains=zeros(count,1,n,nr,'like',matrix);
            for k=1:numel(segments)
                idx=(segments(k).FirstOffset+1):segments(k).EndOffsetExclusive;
                gains(idx,:,:,:)=repmat(reshape(segments(k).Matrix.', ...
                    [1 1 n nr]),[numel(idx) 1 1 1]);
            end
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
                'PhysicalPortMappingApplied',false,'RFIncluded',false, ...
                'BeamFailureRecoveryEpisodeActive',any([segments.EpisodeActive]), ...
                'BeamFailureRecoverySegmentCount',numel(segments));
            if state.Meta.IdentityOperatorSource=="explicit_matrix_AWGN_shared_sample_operator"
                reference.Source="executed_fixed_matrix_AWGN_operator";
                reference.SpatialMatrix=matrix;
            end
        end
    end
end
