function ok=testPDCCHReceiveDecisionBoundary()
% A DCI decision consumes actual monitored symbols, not a padded future slot.
setup6GRSimToolkit('Verbose',false);
random=RandStream('mt19937ar','Seed',9361);
bits=int8(mod((0:31).',2));
for scs=[15 30 60]
    for slot=[0 1 7]
        for startSymbol=[0 3]
            cfg=localConfig(scs,slot,startSymbol);
            prepared=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits);
            count=prepared.MinimumReceiveSamples;
            assert(count<prepared.NumSamples);
            info=nrOFDMInfo(prepared.Tx.Carrier);
            lengths=reshape(info.SymbolLengths,prepared.Tx.Carrier.SymbolsPerSlot,[]);
            assert(count==sum(lengths(1:startSymbol+2,mod(slot,info.SlotsPerSubframe)+1)));
            variance=1e-9;
            noise=sqrt(variance/2)*(randn(random,size(prepared.TransmitSamples))+ ...
                1i*randn(random,size(prepared.TransmitSamples)));
            received=prepared.TransmitSamples+noise;
            prefix=localObservation(received(1:count,:),prepared.RuntimeStartSample,prepared.SampleRateHz);
            [early,earlyInfo]=sixgr.link.completePDCCHReception(prepared,prefix, ...
                'NoiseVariance',variance,'NoiseOnlyWaveform',noise(1:count,:));
            full=localObservation(received,prepared.RuntimeStartSample,prepared.SampleRateHz);
            [later,laterInfo]=sixgr.link.completePDCCHReception(prepared,full,'NoiseVariance',variance);
            assert(early.Ok && later.Ok && isequal(early.DCIBits,bits) && isequal(later.DCIBits,bits));
            assert(earlyInfo.DemodulatedSymbols==startSymbol+2 && ...
                earlyInfo.DemodulatedReceiveSamples==count && ~earlyInfo.ReceivePaddingApplied);
            assert(earlyInfo.ObservationCompletionTime_s<laterInfo.ObservationCompletionTime_s);
            short=localObservation(received(1:count-1,:),prepared.RuntimeStartSample,prepared.SampleRateHz);
            localReject(@() sixgr.link.completePDCCHReception(prepared,short), ...
                'sixgr:link:PDCCHObservationLayoutMismatch');
            pending=sixgr.phy.waveform.WaveformObservationBuffer( ...
                prepared.RuntimeStartSample,prepared.RuntimeStartSample+count,prepared.SampleRateHz,1);
            pending.append(sixgr.phy.waveform.WaveformChunk(received(1:count-1,:), ...
                prepared.RuntimeStartSample),prepared.SampleRateHz);
            localReject(@() sixgr.link.completePDCCHReception(prepared,pending), ...
                'WAVEFORM:IncompleteObservation');
        end
    end
end
shifted=localObservation(received(1:count,:),prepared.RuntimeStartSample+1,prepared.SampleRateHz);
localReject(@() sixgr.link.completePDCCHReception(prepared,shifted), ...
    'sixgr:link:PDCCHObservationOriginMismatch');
wrongRate=localObservation(received(1:count,:),prepared.RuntimeStartSample,2*prepared.SampleRateHz);
localReject(@() sixgr.link.completePDCCHReception(prepared,wrongRate), ...
    'sixgr:link:PDCCHObservationLayoutMismatch');
cfg.lls6g.userContext.RuntimeSlotStartTime_s=0.5/prepared.SampleRateHz;
localReject(@() sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits), ...
    'sixgr:link:PDCCHPreparationClockMismatch');
ok=true;
disp('PDCCH_RECEIVE_DECISION_BOUNDARY_PASS');
end

function cfg=localConfig(scs,slot,startSymbol)
cfg=struct();
cfg.run.seed=9361;
cfg.frequency.duplex_mode='TDD';
cfg.phy.duplex.mode='TDD';
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0, ...
    'SubcarrierSpacing',scs,'NCellID',1,'NSlot',slot,'NFrame',0);
cfg.phy.pdcch=struct('enable',true,'dmrs',struct('enable',true), ...
    'rnti',101,'aggregationLevel',4,'aggregationLevels',4,'blindSearch',true);
cfg.phy.pdcch.coreset=struct('id',0,'duration',2, ...
    'frequencyResources',ones(1,4),'mappingType','noninterleaved');
cfg.phy.pdcch.searchSpace=struct('id',1,'startSymbol',startSymbol, ...
    'numCandidates',[0 0 1 0 0],'slotPeriodAndOffset',[1 0],'duration',1);
% Explicit already-aligned unit fixture; no claim of acquisition coverage.
cfg.lls6g.userContext.RuntimeSlotStartTime_s=slot*1e-3/(scs/15);
end

function buffer=localObservation(samples,start,fs)
buffer=sixgr.phy.waveform.WaveformObservationBuffer(start,start+size(samples,1),fs,size(samples,2));
buffer.append(sixgr.phy.waveform.WaveformChunk(samples,start),fs);
end

function localReject(call,identifier)
try
    call();
catch cause
    assert(strcmp(cause.identifier,identifier), ...
        'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('testPDCCHReceiveDecisionBoundary:MissingRejection','Expected %s.',identifier);
end
