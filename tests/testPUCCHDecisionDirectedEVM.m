function ok=testPUCCHDecisionDirectedEVM()
% Native PUCCH modulation/deprecoding, plus wrong-constellation negatives.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig;
for format=2:4
    for modulation=["QPSK","pi/2-BPSK"]
        if format==2 && modulation~="QPSK", continue; end
        config=feval("nrPUCCH"+format+"Config");
        if format==2
            config.PRBSet=0:1;
            config.SymbolAllocation=[12 2];
        else
            config.Modulation=modulation;
            config.SymbolAllocation=[0 14];
            if format==3
                config.PRBSet=0:1;
            else
                config.PRBSet=0;
                config.SpreadingFactor=2;
            end
        end
        [~,info]=nrPUCCHIndices(carrier,config);
        assert(info.G>=31,'The actual allocation must carry the 20-bit UCI payload and its CRC.');
        bits=int8(mod((0:19)',2));
        coded=nrUCIEncode(bits,info.G);
        symbols=nrPUCCH(carrier,config,coded);
        [~,received]=nrPUCCHDecode(carrier,config,numel(bits),1.03*symbols);
        measured=sixgr.phy.pucch.measureDecisionDirectedEVM(received,true,modulation);
        assert(measured.EVMSymbolCount==numel(received) && ...
            abs(measured.EVMPercent-3)<1e-8 && ...
            measured.EVMReferenceModulation==modulation && ...
            contains(measured.EVMReferenceSource,modulation));
        assert(abs(measured.EVM_rms^2-measured.EVMErrorEnergy/measured.EVMReferenceEnergy)<1e-14);
    end
end
% A QPSK slicer can silently jump to the wrong pi/2-BPSK axis under noise.
wrongAxis=(1-1i)/sqrt(2);
actual=sixgr.phy.pucch.measureDecisionDirectedEVM(wrongAxis,true,"pi/2-BPSK");
assert(actual.EVMPercent>100);
assert(sixgr.phy.pucch.measureDecisionDirectedEVM(wrongAxis,true,"QPSK").EVMPercent<1e-10);
empty=sixgr.phy.pucch.measureDecisionDirectedEVM([],true,"QPSK");
assert(isnan(empty.EVMPercent) && empty.EVMSymbolCount==0);
sequence=sixgr.phy.pucch.measureDecisionDirectedEVM([],false,"QPSK");
assert(~sequence.EVMApplicable && isnan(sequence.EVMPercent));
fprintf('PUCCH_DECISION_DIRECTED_EVM_PASS native_constellation_cases=5\n');
ok=true;
end
