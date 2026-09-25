function rows=runPUCCHFormat2DMRSPresencePilot(configPath,outputRoot)
% Actual native OFDM/received timing pilot; not decoder or held-out qualification.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier pilot results.');
p=sixgr.lls6g.config.readConfigFile(configPath);
assert(string(p.stage)=="development_physical_pilot" && p.episodes_per_case>=1);
carrier=nrCarrierConfig('NSizeGrid',p.carrier.n_size_grid, ...
    'SubcarrierSpacing',p.carrier.subcarrier_spacing_khz,'NCellID',p.carrier.n_cell_id);
pucch=nrPUCCH2Config('PRBSet',p.resource.prb_start+(0:p.resource.prb_count-1), ...
    'SymbolAllocation',[p.resource.symbol_start p.resource.symbol_count], ...
    'NID',p.resource.nid,'NID0',p.resource.nid,'RNTI',p.resource.rnti);
[dataIndices,allocation]=nrPUCCHIndices(carrier,pucch);
pilotIndices=nrPUCCHDMRSIndices(carrier,pucch);
pilotSymbols=nrPUCCHDMRS(carrier,pucch);
window=reshape(p.search_window_samples,1,[]);
assert(numel(window)==2 && window(1)==0 && window(2)>=max(p.transmit_offsets_samples));
rows=table(); episode=0; mkdir(outputRoot);
for branches=reshape(p.receive_branches,1,[])
    for snr=reshape(p.snr_db,1,[])
        for kind=reshape(string(p.observation_types),1,[])
            assert(any(kind==["configured_pucch","noise_only","unrelated_qpsk"]));
            for trial=1:p.episodes_per_case
                episode=episode+1; seed=p.seed_base+episode;
                stream=RandStream('mt19937ar','Seed',seed);
                bits=int8(randi(stream,[0 1],p.payload_bits,1));
                symbols=nrPUCCH(carrier,pucch,nrUCIEncode(bits,allocation.G));
                grid=nrResourceGrid(carrier);
                grid(dataIndices)=symbols; grid(pilotIndices)=pilotSymbols;
                if kind=="noise_only"
                    grid(:)=0;
                elseif kind=="unrelated_qpsk"
                    % Replace ALL data and pilot REs, not just decoded bits.
                    occupied=[dataIndices;pilotIndices];
                    grid(occupied)=nrSymbolModulate(int8(randi(stream,[0 1],2*numel(occupied),1)),'QPSK');
                end
                [tx,info]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
                assert(info.SampleRate==info.Nfft*carrier.SubcarrierSpacing*1000, ...
                    'test:NonNativePilotClock','No resampled-noise assumption in this experiment.');
                [~,demodInfo]=sixgr.phy.waveform.ofdmDemodulate(carrier,tx);
                gridGain=sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
                    1,demodInfo,'InputDomain','sample');
                % Unit-EPRE PUCCH symbols; sample noise follows the actual
                % OFDM transform, and is generated once on EVERY RX branch.
                sampleVariance=10^(-snr/10)/gridGain;
                raw=complex(zeros(size(tx,1)+window(2),branches));
                offset=p.transmit_offsets_samples(mod(trial-1,numel(p.transmit_offsets_samples))+1);
                gains=exp(1i*2*pi*rand(stream,1,branches));
                raw(offset+(1:size(tx,1)),:)=tx*gains;
                raw=raw+sqrt(sampleVariance/2)*(randn(stream,size(raw))+1i*randn(stream,size(raw)));
                [aligned,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
                    carrier,raw,pilotIndices,pilotSymbols,window);
                receivedGrid=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned);
                decision=sixgr.phy.pucch.detectFormat2DMRSPresence(carrier,pucch,receivedGrid, ...
                    p.target_model_false_alarm_probability,diff(window)+1);
                joint=sixgr.phy.pucch.decodeFormat2FlatShortUCI(carrier,pucch,receivedGrid, ...
                    p.payload_bits,p.target_model_false_alarm_probability,diff(window)+1);
                assert(~joint.TransmittedPayloadUsed && ~joint.InjectedNoiseVarianceUsed && ...
                    joint.LayoutHypothesesSearched==1 && ...
                    joint.JointPresenceDecision.HypothesisCount==(diff(window)+1)*2^p.payload_bits);
                assert(~decision.TransmittedPayloadUsed && ~decision.DecodedWordUsed && ...
                    ~decision.InjectedNoiseVarianceUsed && ~decision.PhysicalQualificationPassed && ...
                    ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed);
                assert(decision.NumReceiveAntennas==branches && ...
                    decision.NumReferenceRE==numel(pilotIndices));
                desired=kind=="configured_pucch";
                status="correct_absence_rejection";
                if desired && decision.Detected, status="signal_detected";
                elseif desired, status="missed_signal";
                elseif decision.Detected, status="false_presence";
                end
                row=table(episode,seed,kind,branches,snr,offset,timing.TimingOffsetSamples, ...
                    sampleVariance,decision.Correlation,decision.CorrelationThreshold, ...
                    decision.SearchFalseAlarmBound,decision.HypothesisCount, ...
                    decision.Detected,desired,status,kind=="unrelated_qpsk", ...
                    'VariableNames',{'Episode','Seed','ObservationType','ReceiveBranches','ConfiguredSNR_dB', ...
                    'TXOffsetSamplesAuditOnly','AcquiredOffsetSamples','SampleNoiseVarianceAuditOnly', ...
                    'PilotCorrelation','PilotCorrelationThreshold','ConditionalSearchFalseAlarmBound', ...
                    'SearchedHypotheses','Detected','DesiredPUCCHPresent','Outcome','OutOfGaussianNullStress'});
                row.JointPresenceDetected=joint.JointPresenceDecision.Detected;
                row.JointPresenceSearchFalseAlarmBound=joint.JointPresenceDecision.SearchFalseAlarmBound;
                row.JointConditionalWordPosterior=joint.ConditionalWordPosterior;
                row.JointBitErrors=NaN;
                if desired, row.JointBitErrors=nnz(joint.Bits~=bits); end
                rows=[rows;row]; %#ok<AGROW>
                writetable(rows,fullfile(outputRoot,'physical_pilot.csv'));
            end
        end
    end
end
sixgr.util.jsonWrite(fullfile(outputRoot,'scope.json'),struct( ...
    'Scope',"native_Format2_DMRS_waveform_development_pilot_not_decoder_qualification", ...
    'InputConfig',string(configPath),'PolicySHA256',sixgr.util.sha256File(configPath), ...
    'Episodes',height(rows),'CandidatePolicyInstalled',false,'DetectorQualified',false, ...
    'ThresholdTuned',false,'Channel',"unit_gain_static_complex_SIMO", ...
    'Noise',"one_independent_white_circular_Gaussian_stream_per_complete_capture", ...
    'RFImpairmentsApplied',false,'FullReceiverExecuted',false, ...
    'DecoderAndHARQAcceptanceQualified',false,'MATLABVersion',version, ...
    'JointDecoderSHA256',sixgr.util.sha256File(which('sixgr.phy.pucch.decodeFormat2FlatShortUCI'))));
fprintf('PUCCH_FORMAT2_DMRS_PILOT_COMPLETE episodes=%d qualification=0 installed=0 csv=%s\n', ...
    height(rows),fullfile(outputRoot,'physical_pilot.csv'));
end
