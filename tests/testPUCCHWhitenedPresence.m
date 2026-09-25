function ok=testPUCCHWhitenedPresence()
% Actual OFDM/DM-RS/equalizer checks plus an independent legal-word reference.
% Development evidence only: no threshold tuning or qualification declaration.
setup6GRSimToolkit('Verbose',false);
configPath=fullfile('simulator','configs','validation','pucch_whitened_presence_component.yaml');
p=sixgr.lls6g.config.readConfigFile(configPath);
assert(string(p.stage)=="physical_receiver_component_not_statistical_qualification" && ...
    string(p.receiver_fixture)=="PUCCHFixtureFactory_connected_format2");
stream=RandStream('Threefry','Seed',p.seed);
folder=fullfile(pwd,'logs',['pucch_whitened_presence_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder); rows=table(); independentPilotChecks=0;
for count=reshape(p.payload_bits,1,[])
    bits=int8(randi(stream,[0 1],count,1));
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',p.rnti);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    resource=f.Assignment.Resource.toolboxConfig();
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_whitened_presence", ...
        'ConfigurationEpoch',1,'Sequence1Length',count,'Sequence2Length',0, ...
        'HARQACKBits',0,'SRBits',0,'CSIPart1Bits',count,'CSIPart2Bits',0,'PriorityIndex',0));
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
        'ObservationID',"gnb_whitened_presence",'ResourceID',p.resource_id,'RNTI',p.rnti, ...
        'AbsoluteSlot0',0,'Source',"declared_gNB_presence_unit_fixture", ...
        'TimingSource',"unit_fixture_received_DMRS_acquisition", ...
        'ResourceSelectionProcedure',"configured_csi"),f.RRCContext,context);
    for branches=reshape(p.receive_branches,1,[])
        gains=reshape(p.channel_gain_amplitude(1:branches),1,[]).* ...
            exp(1i*reshape(p.channel_gain_phase_rad(1:branches),1,[]));
        signal=tx.Waveform*gains;
        energy=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
            f.Carrier,signal,tx.PUCCHIndices,'SignalFamily','PUCCH');
        [~,ofdm]=sixgr.phy.waveform.ofdmDemodulate(f.Carrier,signal);
        transform=sixgr.phy.waveform.convertNoiseVarianceToGridDomain(1,ofdm,'InputDomain','sample');
        window=reshape(p.search_window_samples,1,[]); transmitOffset=p.transmit_offset_samples;
        % Actual waveform with silent TX prefix/tail, and independent noise
        % throughout the capture. The receiver never receives transmitOffset.
        delayed=complex(zeros(size(signal,1)+window(2),branches));
        delayed(transmitOffset+(1:size(signal,1)),:)=signal;
        for snr=reshape(p.snr_db,1,[])
            variance=energy/10^(snr/10)/transform;
            noise=sqrt(variance/2)*(randn(stream,size(delayed))+1i*randn(stream,size(delayed)));
            for present=[true false]
                samples=double(present)*delayed+noise;
                rx=sixgr.phy.pucch.PUCCHReceiver.receive(samples,f.Carrier,assignment,context, ...
                    'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
                    'ChannelProfile','AWGN','DetectionThreshold',p.legacy_detection_threshold, ...
                    'TimingSearchWindowSamples',window);
                assert(~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
                searches=diff(rx.ReceiveTiming.SearchWindowSamples)+1;
                r=rx.EqualizerInfo.EqualizerResult;
                decision=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
                    f.Carrier,resource,r,count,p.target_model_false_alarm_probability,searches);
                assert(~decision.PhysicalQualificationPassed && ...
                    ~decision.NoiseModelEstablishedByThisFunction && ...
                    ~decision.InjectedNoiseVarianceUsed && ~decision.TransmittedPayloadUsed && ...
                    decision.LayoutHypothesesSearched==1 && decision.HypothesisCount==searches*2^count);
                if present && snr==max(p.snr_db), assert(decision.Detected,'Strong desired waveform must be detected.'); end
                % Direct public whole-word coding and row norm, independently
                % of the candidate's linear-basis reference construction.
                if count==min(p.payload_bits)
                    W=reshape(r.W,[],branches); normW=sqrt(sum(abs(W).^2,2));
                    y=r.EqualizedSymbols(:)./normW;
                    gain=r.EffectiveResponseWH(:)./normW;
                    correlations=zeros(2^count,1);
                    [~,allocation]=nrPUCCHIndices(f.Carrier,resource);
                    for word=0:2^count-1
                        message=int8(bitget(uint16(word),(1:count).'));
                        reference=gain.*nrPUCCH(f.Carrier,resource,nrUCIEncode(message,allocation.G));
                        correlations(word+1)=abs(reference'*y)/norm(reference)/norm(y);
                    end
                    assert(abs(decision.Correlation-max(correlations))<1e-12);
                end
                % Critical precondition: changing only data REs must not
                % change the fitted channel/equalizer used in the null law.
                acquired=rx.ReceiveTiming.AppliedTimingCorrectionSamples;
                aligned=samples(acquired+(1:rx.ReceiveTiming.DemodulatedSampleCount),:);
                grid=sixgr.phy.waveform.ofdmDemodulate(f.Carrier,aligned);
                [idx,~]=nrPUCCHIndices(f.Carrier,resource);
                pilotIdx=nrPUCCHDMRSIndices(f.Carrier,resource);
                pilots=nrPUCCHDMRS(f.Carrier,resource);
                [h,nv]=sixgr.phy.rx.channelEstimate(f.Carrier,grid,pilotIdx,pilots);
                assert(isequaln(h,rx.ChannelEstimate) && isequaln(nv,rx.GridNoiseVariance), ...
                    'test:DifferentPUCCHEstimatorPath','Verify the actually executed receiver estimator.');
                poisoned=reshape(grid,[],branches);
                poisoned(idx,:)=p.data_poison_amplitude*(randn(stream,numel(idx),branches)+1i*randn(stream,numel(idx),branches));
                poisoned=reshape(poisoned,size(grid));
                [otherH,otherNV]=sixgr.phy.rx.channelEstimate(f.Carrier,poisoned,pilotIdx,pilots);
                assert(isequaln(h,otherH) && isequaln(nv,otherNV), ...
                    'test:DataDependentPUCCHEstimator', ...
                    'The conditional white-noise detector cannot use data-dependent channel/noise estimates.');
                independentPilotChecks=independentPilotChecks+1;
                scaled=r; scaled.W=p.equalizer_scale_probe*r.W;
                scaled.EqualizedSymbols=p.equalizer_scale_probe*r.EqualizedSymbols;
                scaled.EffectiveResponseWH=p.equalizer_scale_probe*r.EffectiveResponseWH;
                invariant=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
                    f.Carrier,resource,scaled,count,p.target_model_false_alarm_probability,searches);
                assert(abs(invariant.Correlation-decision.Correlation)<1e-12 && ...
                    invariant.Detected==decision.Detected);
                searched=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
                    f.Carrier,resource,r,count,p.target_model_false_alarm_probability,p.wider_search_hypothesis_count);
                assert(searched.HypothesisCount==p.wider_search_hypothesis_count*2^count && ...
                    searched.CorrelationThreshold>=decision.CorrelationThreshold && ...
                    (~searched.Detected || decision.Detected));
                row=table(count,branches,snr,present,transmitOffset,acquired,searches,rx.DetectionMetric,~rx.DTX, ...
                    decision.Correlation,decision.CorrelationThreshold,decision.Detected, ...
                    decision.SearchFalseAlarmBound,searched.Detected, ...
                    'VariableNames',{'PayloadBits','ReceiveBranches','FixtureSNRdB','ProducerPresent', ...
                    'TransmitOffsetAuditOnly','AcquiredOffsetSamples','SearchedTimingHypotheses', ...
                    'LegacyMetric','LegacyDetected','WhitenedCorrelation','WhitenedThreshold', ...
                    'ConditionalDetected','ConditionalSearchBound','DetectedAfterWiderSearchAccounting'});
                rows=[rows;row]; %#ok<AGROW>
                writetable(rows,fullfile(folder,'physical_component.csv'));
            end
        end
    end
end
invalid=r; invalid.W(:)=NaN;
rejected=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
    f.Carrier,resource,invalid,count,p.target_model_false_alarm_probability,searches);
assert(~rejected.Detected && rejected.Status=="invalid_equalizer_observation");
sixgr.util.jsonWrite(fullfile(folder,'scope.json'),struct('Config',p, ...
    'ConfigSHA256',sixgr.util.sha256File(configPath),'Source',"actual_OFDM_DMRS_equalizer_component", ...
    'DetectorQualified',false,'PolicyInstalled',false,'ThresholdTuned',false, ...
    'HelperSHA256',sixgr.util.sha256File(which('sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence'))));
fprintf('PUCCH_WHITENED_PRESENCE_PASS cases=%d independent_pilot_checks=%d noise_only_detected=%d/%d qualification=0 folder=%s\n', ...
    height(rows),independentPilotChecks,nnz(~rows.ProducerPresent & rows.ConditionalDetected), ...
    nnz(~rows.ProducerPresent),folder);
ok=true;
end
