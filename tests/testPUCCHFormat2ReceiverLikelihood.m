function ok=testPUCCHFormat2ReceiverLikelihood()
% Actual Format-2 waveform/DM-RS/MMSE receiver integration, not qualification.
% The analytic two-branch connector is an explicit unit fixture; the receiver
% gets only the independently installed resource/schema and captured samples.
setup6GRSimToolkit('Verbose',false);
stream=RandStream('Threefry','Seed',4702626);
root=fullfile(pwd,'logs',['pucch_receiver_likelihood_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(root); rows=table();
for count=[11 32]
    bits=int8(randi(stream,[0 1],count,1));
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',321);
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_likelihood", ...
        'ConfigurationEpoch',1,'Sequence1Length',count,'Sequence2Length',0, ...
        'HARQACKBits',0,'SRBits',0,'CSIPart1Bits',count,'CSIPart2Bits',0,'PriorityIndex',0));
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
        'ObservationID',"gnb_likelihood",'ResourceID',12,'RNTI',321, ...
        'AbsoluteSlot0',0,'Source',"declared_gNB_likelihood_unit_fixture", ...
        'TimingSource',"unit_fixture_aligned_capture", ...
        'ResourceSelectionProcedure',"configured_csi"),f.RRCContext,context);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    desired=tx.Waveform*[.013+.004i .009-.006i];
    energy=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        f.Carrier,desired,tx.PUCCHIndices,'SignalFamily','PUCCH');
    [~,ofdm]=sixgr.phy.waveform.ofdmDemodulate(f.Carrier,desired);
    transform=sixgr.phy.waveform.convertNoiseVarianceToGridDomain(1,ofdm,'InputDomain','sample');
    for snr=[-10 20]
        variance=energy/10^(snr/10)/transform;
        noise=sqrt(variance/2)*(randn(stream,size(desired))+1i*randn(stream,size(desired)));
        for present=[true false]
            observed=double(present)*desired+noise;
            rx=sixgr.phy.pucch.PUCCHReceiver.receive(observed,f.Carrier,assignment,context, ...
                'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
                'ChannelProfile','AWGN','DetectionThreshold',.2);
            assert(isfield(rx,'UCICodewordLLR') && isfield(rx,'DemapperEvidence'), ...
                'test:PUCCHGainAwareLikelihoodNotIntegrated', ...
                'The actual receiver must use and retain its per-RE gain-aware UCI likelihood.');
            result=rx.EqualizerInfo.EqualizerResult;
            y=result.EqualizedSymbols(:); g=result.EffectiveResponseWH(:);
            v=result.OutputNoiseInterferenceCovariance(:);
            reference=zeros(2*numel(y),1);
            for k=1:numel(y)
                if g(k)==0, continue; end % Zero response carries no bit information.
                reference(2*k-1:2*k)=nrSymbolDemodulate(y(k)/g(k),'QPSK',real(v(k))/abs(g(k))^2);
            end
            resource=assignment.Resource.toolboxConfig();
            nid=resource.NID; if isempty(nid), nid=f.Carrier.NCellID; end
            reference=reference.*nrPUCCHPRBS(nid,resource.RNTI,numel(reference),'MappingType','signed');
            error=max(abs(rx.UCICodewordLLR-reference));
            assert(error<1e-10*max(1,max(abs(reference))) && ...
                ~rx.DemapperEvidence.MeanVarianceUsed && ~rx.DemapperEvidence.TransmittedBitsUsed && ...
                ~rx.DemapperEvidence.SignalPresenceDecisionMade && ~rx.DemapperEvidence.PhysicalQualificationPassed);
            decoded=sixgr.phy.pucch.UCIDecoder.decode(reference,count);
            assert(rx.CRCApplicable==(count>=12) && rx.CRCPassed==decoded.CRCPassed && ...
                isequal(rx.CodeBlockCRCError,decoded.CodeBlockCRCError));
            if rx.DTX
                assert(isempty(rx.DecodedSequence1) && ~rx.ReceiverUsable);
            else
                assert(isequal(rx.DecodedSequence1,decoded.Bits));
            end
            % Freeze the existing presence decision. A decoder change must
            % neither tune the threshold nor rescue failed/invalid detection.
            [~,~,metric]=nrPUCCHDecode(f.Carrier,resource,count,y, ...
                rx.DecodeNoiseInterferenceVariance,'DetectionThreshold',.2);
            ratio=mean(abs(y).^2)/max(rx.DecodeNoiseInterferenceVariance,eps);
            [expectedMetric,source]=sixgr.phy.pucch.PUCCHDetector.selectMetric(2,false,metric,ratio,count);
            decision=sixgr.phy.pucch.PUCCHDetector.decide(2,expectedMetric,.2,int8([]));
            assert(isequaln(rx.DetectionMetric,expectedMetric) && rx.DetectionMetricSource==source && ...
                rx.DTX==decision.DTX && rx.DetectionThreshold==.2 && rx.ReceiverOnlyAssignment && ...
                ~rx.OraclePayloadBitsUsed && isnan(rx.SampleNoiseVariance));
            if present && snr==20
                assert(~rx.DTX && rx.CRCPassed && isequal(rx.DecodedSequence1,bits));
            end
            row=table(count,snr,present,error,rx.DTX,rx.CRCApplicable,rx.CRCPassed, ...
                'VariableNames',{'PayloadBits','FixtureSNRdB','ProducerPresent','MaximumLLRError', ...
                'DTX','CRCApplicable','CRCPassed'});
            rows=[rows;row]; %#ok<AGROW>
            writetable(rows,fullfile(root,'receiver_likelihood.csv'));
        end
    end
end
% Explicit zero-disturbance unit references retain their separate endpoint;
% zero variance must not silently replace a received pilot-noise estimate.
zero=sixgr.phy.pucch.PUCCHReceiver.receive(desired,f.Carrier,assignment,context, ...
    'NoiseVariance',0,'NoiseVarianceMode','provided','ChannelProfile','AWGN','DetectionThreshold',.2);
assert(zero.DemapperEvidence.Source=="provided_zero_disturbance_toolbox_decode" && ...
    zero.DemapperEvidence.NoiselessReference && ~zero.DemapperEvidence.PerREGainAware && ...
    ~zero.DTX && zero.CRCPassed && isequal(zero.DecodedSequence1,bits));
fprintf('PUCCH_RECEIVER_LIKELIHOOD_PASS physical_cases=%d detector_policy_changed=0 qualification=0 evidence=%s\n',height(rows),root);
ok=true;
end
