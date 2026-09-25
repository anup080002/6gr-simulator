function ok=testPUCCHFlatJointShortUCI()
% Independently solve LS residuals using public whole-word PUCCH waveforms.
% Mathematical/codec checks only, not a physical false/missed-ACK campaign.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
stream=RandStream('mt19937ar','Seed',p.seed);
carrier=nrCarrierConfig; pucch=nrPUCCH2Config('SymbolAllocation',[12 2]);
cases=0;
for a=reshape(p.codec_payload_bits,1,[])
    for e=reshape(p.codec_coded_lengths,1,[])
        pucch.PRBSet=0:(e/32-1);
        [indices,allocation]=nrPUCCHIndices(carrier,pucch);
        pilots=nrPUCCHDMRS(carrier,pucch); pilotIndices=nrPUCCHDMRSIndices(carrier,pucch);
        bits=int8(randi(stream,[0 1],a,1));
        symbols=nrPUCCH(carrier,pucch,nrUCIEncode(bits,allocation.G));
        branches=p.demapper_receive_branches(mod(cases,numel(p.demapper_receive_branches))+1);
        grid=nrResourceGrid(carrier,branches);
        samples=reshape(grid,[],branches);
        gain=exp(1i*2*pi*rand(stream,1,branches));
        occupied=[indices;pilotIndices];
        y=[symbols;pilots]*gain+(randn(stream,numel(occupied),branches)+ ...
            1i*randn(stream,numel(occupied),branches))/(sqrt(2)*p.strong_llr_magnitude);
        samples(occupied,:)=y; grid=reshape(samples,size(grid));
        decision=sixgr.phy.pucch.decodeFormat2FlatShortUCI( ...
            carrier,pucch,grid,a,p.target_model_probability,1);
        assert(isequal(decision.Bits,bits) && decision.UniqueMaximum && ...
            decision.JointPresenceDecision.Detected && ~decision.TransmittedPayloadUsed && ...
            ~decision.InjectedNoiseVarianceUsed && ~decision.PhysicalQualificationPassed && ...
            decision.LayoutHypothesesSearched==1 && decision.CandidateCount==2^a);
        % Full public encoding (not linear-basis construction), independent
        % complex LS solve and direct residuals for all eight three-bit words.
        if a==min(p.codec_payload_bits)
            residual=zeros(2^a,1);
            for w=0:2^a-1
                word=int8(bitget(uint16(w),(1:a).'));
                ref=[nrPUCCH(carrier,pucch,nrUCIEncode(word,allocation.G));pilots];
                response=ref\y;
                residual(w+1)=sum(abs(y-ref*response).^2,'all');
            end
            scores=-branches*(size(y,1)-1)*log(residual);
            weights=exp(scores-max(scores)); posterior=weights/sum(weights);
            [maximum,winner]=max(posterior);
            assert(isequal(decision.Bits,int8(bitget(uint16(winner-1),(1:a).'))) && ...
                abs(decision.ConditionalWordPosterior-maximum)<1e-12);
            scaled=sixgr.phy.pucch.decodeFormat2FlatShortUCI(carrier,pucch,grid*1e-4, ...
                a,p.target_model_probability,1);
            assert(isequal(scaled.Bits,decision.Bits) && ...
                abs(scaled.JointPresenceDecision.Correlation-decision.JointPresenceDecision.Correlation)<1e-12);
        end
        cases=cases+1;
    end
end
absent=sixgr.phy.pucch.decodeFormat2FlatShortUCI(carrier,pucch,zeros(size(grid)), ...
    a,p.target_model_probability,1);
assert(isempty(absent.Bits) && absent.Status=="zero_received_energy");
fprintf('PUCCH_FLAT_JOINT_SHORT_UCI_MATH_PASS cases=%d physical_qualification=0\n',cases);
ok=true;
end
