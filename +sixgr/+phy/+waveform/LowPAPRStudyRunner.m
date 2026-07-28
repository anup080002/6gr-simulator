classdef LowPAPRStudyRunner
    %LOWPAPRSTUDYRUNNER Paired canonical CP-OFDM/DFT-s-OFDM execution.
    methods (Static)
        function result=run(cfg,numTrials)
            if nargin<2,numTrials=8;end
            [carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
            modulation=upper(string(sixgr.util.structGet(cfg,"phy.pusch.modulation","")));
            if strlength(modulation)==0
                error("WAVEFORM:UnsupportedModulation", ...
                    "phy.pusch.modulation must be configured explicitly.");
            end
            bitsPerSymbol=sixgr.phy.waveform.LowPAPRStudyRunner.bitsPerSymbol(modulation);
            prbSet=sixgr.phy.waveform.LowPAPRStudyRunner. ...
                resolvePRBSet(cfg,double(carrier.NSizeGrid));
            nRB=numel(prbSet); m=12*nRB;
            if m>=sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier).Nfft
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "Localized DFT-s-OFDM requires Nfft greater than M.");
            end
            epoch=double(sixgr.util.structGet(cfg,"run.configurationEpoch",0));
            assignment=struct("Decoded",true,"LayerCount",1,"PRBCount",nRB, ...
                "Contiguous",true,"ConfigurationEpoch",epoch, ...
                "CurrentConfigurationEpoch",epoch, ...
                "PTRSSymbolPartitionExact",true,"Modulation",modulation);
            plan=sixgr.phy.waveform.TransformPrecodingPlan( ...
                assignment,"nr_rel19_ul_dfts_ofdm_strict"); %#ok<NASGU>
            symbolsPerSlot=double(carrier.SymbolsPerSlot);
            seed=double(sixgr.util.structGet(cfg,"run.seed",1));
            stream=RandStream("mt19937ar","Seed",seed);
            rows=table();
            cpPAPR=zeros(numTrials,1);dftPAPR=zeros(numTrials,1);
            evmCP=zeros(numTrials,1);evmDFT=zeros(numTrials,1);
            for trial=1:numTrials
                bits=int8(randi(stream,[0 1],m*symbolsPerSlot*bitsPerSymbol,1));
                if ismember(modulation,["PI/2-BPSK","PI2-BPSK"])
                    symbols=sixgr.phy.waveform.PiOver2BPSKMapper.map(bits,0);
                else
                    [symbols,~]=sixgr.phy.mod.modulate(bits,char(modulation));
                end
                symbols=reshape(symbols,m,symbolsPerSlot);
                spread=sixgr.phy.waveform.UnitaryDFTSpreader.apply(symbols,m);
                allocatedRows=reshape(12*prbSet(:).' + (1:12).',[],1);
                cpTxGrid=complex(zeros(12*double(carrier.NSizeGrid), ...
                    symbolsPerSlot));
                dftTxGrid=cpTxGrid;
                cpTxGrid(allocatedRows,:)=symbols;
                dftTxGrid(allocatedRows,:)=spread;
                [cpWave,cpInfo]=sixgr.phy.waveform.CanonicalOFDMModulator.toolbox( ...
                    carrier,cpTxGrid,"Windowing",0);
                [dftWave,dftInfo]=sixgr.phy.waveform.CanonicalOFDMModulator.toolbox( ...
                    carrier,dftTxGrid,"Windowing",0);
                cpRxGrid=sixgr.phy.waveform.CanonicalOFDMDemodulator.toolbox( ...
                    carrier,cpWave,"Windowing",0);
                dftRxGrid=sixgr.phy.waveform.CanonicalOFDMDemodulator.toolbox( ...
                    carrier,dftWave,"Windowing",0);
                cpGrid=cpRxGrid(allocatedRows,:);
                dftGrid=dftRxGrid(allocatedRows,:);
                recovered=sixgr.phy.waveform.UnitaryDFTDespreader.apply( ...
                    dftGrid,m);
                evmCP(trial)=100*sqrt(mean(abs(cpGrid(:)-symbols(:)).^2)/ ...
                    max(mean(abs(symbols(:)).^2),eps));
                evmDFT(trial)=100*sqrt(mean(abs(recovered(:)-symbols(:)).^2)/ ...
                    max(mean(abs(symbols(:)).^2),eps));
                cpMeasures=sixgr.phy.waveform.PAPRMeasurement.measure( ...
                    cpWave,[1 2 4 8],"PayloadID","PAYLOAD-"+trial);
                dftMeasures=sixgr.phy.waveform.PAPRMeasurement.measure( ...
                    dftWave,[1 2 4 8],"PayloadID","PAYLOAD-"+trial);
                cpPAPR(trial)=cpMeasures.PAPR_dB(end);
                dftPAPR(trial)=dftMeasures.PAPR_dB(end);
                one=table(repmat(trial,8,1), ...
                    [repmat("CP-OFDM",4,1);repmat("DFT-s-OFDM",4,1)], ...
                    [cpMeasures.OversamplingFactor;dftMeasures.OversamplingFactor], ...
                    [cpMeasures.PAPR_dB;dftMeasures.PAPR_dB], ...
                    repmat(string(cpInfo.SampleRate),8,1), ...
                    repmat("PAYLOAD-"+trial,8,1), ...
                    repmat(sixgr.phy.waveform.WaveformHash.numeric(bits),8,1), ...
                    'VariableNames',{'TrialID','Mode','OversamplingFactor', ...
                    'PAPR_dB','SampleRate_Hz','PayloadID','ResourceDigest'});
                rows=[rows;one]; %#ok<AGROW>
                assert(cpInfo.OFDMWindowingSamples==0 && dftInfo.OFDMWindowingSamples==0);
            end
            result=struct("PAPR_CP_dB",mean(cpPAPR), ...
                "PAPR_DFTs_dB",mean(dftPAPR), ...
                "PAPR_Gain_dB",mean(cpPAPR)-mean(dftPAPR), ...
                "EVM_CP_pct",mean(evmCP),"EVM_DFT_pct",mean(evmDFT), ...
                "Trials",rows,"Carrier",carrier, ...
                "ExecutionBackend","canonical_waveform_truth", ...
                "ApproximationMode","none", ...
                "WindowingSamples",0);
        end
    end
    methods (Static,Access=private)
        function prbSet=resolvePRBSet(cfg,nSizeGrid)
            prbSet=sixgr.util.structGet(cfg,"phy.pusch.PRBSet",[]);
            if isempty(prbSet)
                prbSet=sixgr.util.structGet(cfg,"phy.pusch.prbSet",[]);
            end
            prbSet=double(prbSet(:)).';
            if isempty(prbSet)
                error("WAVEFORM:MissingTransformAllocation", ...
                    "Localized DFT-s-OFDM requires an explicit PUSCH PRBSet.");
            end
            if any(~isfinite(prbSet)) || any(prbSet~=fix(prbSet)) || ...
                    any(prbSet<0) || any(prbSet>=nSizeGrid) || ...
                    numel(unique(prbSet))~=numel(prbSet)
                error("WAVEFORM:InvalidTransformAllocation", ...
                    "PUSCH PRBSet must contain unique zero-based PRB indices inside the carrier.");
            end
            prbSet=sort(prbSet);
            if numel(prbSet)>1 && any(diff(prbSet)~=1)
                error("WAVEFORM:NoncontiguousTransformAllocation", ...
                    "Localized DFT-s-OFDM requires a contiguous PUSCH PRBSet.");
            end
        end
        function value=bitsPerSymbol(modulation)
            switch modulation
                case {"BPSK","PI/2-BPSK","PI2-BPSK"},value=1;
                case "QPSK",value=2;
                case "16QAM",value=4;
                case "64QAM",value=6;
                case "256QAM",value=8;
                otherwise
                    error("WAVEFORM:UnsupportedModulation", ...
                        "Modulation '%s' is unsupported by the selected profile.",modulation);
            end
        end
    end
end
