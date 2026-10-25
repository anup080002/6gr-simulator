function ok=testActiveOFDMNonzeroSlotPower()
% Native OFDM sample-interval regression, not a receiver/RF qualification.
setup6GRSimToolkit('Verbose',false);
cases=0;
for scs=[15 30 60 120]
    carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',scs);
    carrier.NFrame=2;
    for slot=0:carrier.SlotsPerSubframe-1
        carrier.NSlot=carrier.SlotsPerSubframe+slot;
        for slotCount=[1 3]
            count=double(carrier.SymbolsPerSlot)*slotCount;
            grid=complex(zeros(288,count,2));
            for symbol=1:count
                grid(25:48,symbol,1)=exp(1i*(1:24).'/7)*(1+symbol/10);
                grid(61:84,symbol,2)=exp(-1i*(1:24).'/5)*(2+symbol/20);
            end
            [x,info]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
            [native,nativeInfo]=nrOFDMModulate(carrier,grid,'Windowing',0);
            assert(isequal(x,native) && info.InitialSlotInSubframe==slot);
            nfft=double(nativeInfo.Nfft); cp=double(nativeInfo.CyclicPrefixLengths(:));
            % Independent direct native sample accounting across subframes.
            index=mod(slot*carrier.SymbolsPerSlot+(0:count-1),numel(cp))+1;
            actualCP=cp(index); actualCP=actualCP(:);
            starts=[0;cumsum(nfft+actualCP(1:end-1))];
            assert(sum(nfft+actualCP)==size(x,1));
            selected=[0 count-1];
            used=zeros(0,1);
            for symbol=selected
                used=[used;starts(symbol+1)+actualCP(symbol+1)+(1:nfft).']; %#ok<AGROW>
            end
            expected=mean(abs(double(native(used,:))).^2,1);
            [total,perPort,receipt]=sixgr.rf.measureActiveOFDMTotalPower(x, ...
                struct('OFDM',info),'ActiveSymbolIndices',selected);
            assert(isequal(perPort,expected) && total==sum(expected) && ...
                receipt.TotalSymbolCount==count && receipt.ActiveSymbolCount==2 && ...
                receipt.SampleCount==numel(used)*2 && ...
                isequal(receipt.ActiveSymbolIndices,selected.'));
            reject(@()sixgr.rf.measureActiveOFDMTotalPower(x(1:end-1,:), ...
                struct('OFDM',info),'ActiveSymbolIndices',count-1), ...
                'sixgr:rf:ActiveOFDMSymbolOutsideWaveform');
            if scs>=60
                missing=rmfield(info,'InitialSlotInSubframe');
                reject(@()sixgr.rf.measureActiveOFDMTotalPower(x,struct('OFDM',missing)), ...
                    'sixgr:rf:ActiveOFDMClockOriginRequired');
                bad=info; bad.InitialSlotInSubframe=carrier.SlotsPerSubframe;
                reject(@()sixgr.rf.measureActiveOFDMTotalPower(x,struct('OFDM',bad)), ...
                    'sixgr:rf:ActiveOFDMClockMetadata');
            end
            cases=cases+1;
        end
    end
end
% The failing public producer must also retain its nonzero native origin.
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,[],'SCS',60);
f.Carrier.NFrame=1; f.Carrier.NSlot=1;
data=f.Report.Data; data.TargetSlot=42;
f.Report=sixgr.phy.pucch.UCIReport(data);
frame=f.FrameState; frame.PDSCHEndSlot=41; frame.TargetSlot=42;
f.Assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(f.Report,f.UEContext,frame);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
assert(tx.OFDMInfo.InitialSlotInSubframe==1 && ...
    abs(tx.Power.MeasuredWaveformPowerdBm-tx.Power.AppliedPowerdBm)<1e-10);
fprintf('ACTIVE_OFDM_NONZERO_SLOT_POWER_PASS native_cases=%d public_pucch_tx=1\n',cases);
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
