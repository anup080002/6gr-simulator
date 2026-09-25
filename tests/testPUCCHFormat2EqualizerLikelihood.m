function ok=testPUCCHFormat2EqualizerLikelihood()
% Public Toolbox QPSK likelihood and scrambling comparison, not qualification.
setup6GRSimToolkit('Verbose',false);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
stream=RandStream('mt19937ar','Seed',p.seed);
carrier=nrCarrierConfig; resource=nrPUCCH2Config;
resource.SymbolAllocation=[12 2];
% Published PRBS example identities; both explicit and cell-inherited NID.
carrier.NCellID=17; resource.RNTI=120;
cases=0;
for explicitIdentity=[false true]
    resource.NID=[];
    if explicitIdentity, resource.NID=carrier.NCellID; end
    for a=[reshape(p.codec_payload_bits,1,[]) reshape(p.format2_crc_payload_bits,1,[])]
        for e=reshape(p.codec_coded_lengths,1,[])
            % Format 2: eight data REs/PRB/symbol and two bits per QPSK RE.
            resource.PRBSet=0:(e/32-1);
            bits=int8(randi(stream,[0 1],a,1));
            coded=nrUCIEncode(bits,e); symbols=nrPUCCH(carrier,resource,coded);
            n=numel(symbols);
            gain=(.1+rand(stream,n,1)).*exp(1i*rand(stream,n,1));
            variance=(.1+rand(stream,n,1))/p.strong_llr_magnitude^2;
            observed=gain.*symbols+sqrt(variance/2).*(randn(stream,n,1)+1i*randn(stream,n,1));
            result=struct('EqualizedSymbols',observed,'EffectiveResponseWH',gain, ...
                'OutputNoiseInterferenceCovariance',variance,'NumTxPorts',1, ...
                'NoiseAddedExactlyOnce',true,'SymbolCovarianceConvention',"unit_layer_symbol_covariance");
            [llr,evidence]=sixgr.phy.pucch.demapFormat2EqualizerOutput(carrier,resource,result);
            public=zeros(e,1);
            for k=1:n
                public(2*k-1:2*k)=nrSymbolDemodulate(observed(k)/gain(k), ...
                    'QPSK',variance(k)/abs(gain(k))^2);
            end
            public=public.*nrPUCCHPRBS(carrier.NCellID,resource.RNTI,e,'MappingType','signed');
            assert(max(abs(llr-public))<1e-10 && evidence.CodedBitCount==e && ...
                ~evidence.SignalPresenceDecisionMade && ~evidence.PhysicalQualificationPassed);
            ours=sixgr.phy.pucch.UCIDecoder.decode(llr,a);
            reference=sixgr.phy.pucch.UCIDecoder.decode(public,a);
            assert(isequal(ours.Bits,reference.Bits) && ours.CRCApplicable==(a>=12) && ...
                isequal(ours.CodeBlockCRCError,reference.CodeBlockCRCError) && ...
                ours.CRCPassed==reference.CRCPassed);
            cases=cases+1;
        end
    end
end
bad=result; bad.EqualizedSymbols=bad.EqualizedSymbols(2:end);
reject(@()sixgr.phy.pucch.demapFormat2EqualizerOutput(carrier,resource,bad));
reject(@()sixgr.phy.pucch.demapFormat2EqualizerOutput(carrier,nrPUCCH3Config,result));
if isprop(resource,'Interlacing')
    resource.Interlacing=true;
    reject(@()sixgr.phy.pucch.demapFormat2EqualizerOutput(carrier,resource,result));
end
fprintf('PUCCH_FORMAT2_EQUALIZER_LIKELIHOOD_PASS cases=%d physical_qualification=0\n',cases);
ok=true;
end
function reject(fn)
try
    fn();
catch cause
    assert(startsWith(string(cause.identifier),'sixgr:phy:')); return;
end
error('test:InvalidFormat2DemapperAccepted','Malformed evidence must be rejected.');
end
