function ok = testControlSoftDemapperIntegration()
% Exercise the actual generic demapper consumer, not a standalone formula.
% This is the ctrl study coding convention, not full NR PDCCH conformance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg = struct('Modulation','QPSK','PayloadLengthBits',44,'CRCPolynomial','24C', ...
    'RNTI',4660,'CellID',73,'PolarListLength',8,'CRCScramblingEnabled',true, ...
    'PayloadScramblingEnabled',true,'PayloadSequenceInit',73,'PDCCHScramblingID',73);
bits = int8(mod(floor((0:43).'/3),2));
crc = sixgr.ctrl.CRCAttachAndScramble(bits,cfg);
for al = [1 4 16]
    E = 108*al;
    mother = nrPolarEncode(crc.BitsWithCRC,E,9,false);
    encoded = nrRateMatchPolar(mother,numel(crc.BitsWithCRC),E,false);
    scrambled = sixgr.ctrl.PayloadScrambler(encoded,cfg,struct());
    tx = sixgr.ctrl.PDCCHModulator(scrambled.Bits,cfg);
    phase = (0:numel(tx.Symbols)-1).';
    observed = tx.Symbols+.005*(sin(phase)+1i*cos(phase));
    for variance = {.01, .01+.001*mod(phase,3)}
        rx = sixgr.ctrl.PDCCHDecoder(observed,variance{1},[],cfg,struct());
        assert(rx.CRCPass && isequal(rx.DecodedBits,bits),'Actual control consumer did not recover the coded payload.');
        assert(rx.DemodInfo.LLRAlgorithmApplied=="exact_log_sum_exp");
        reference = nrSymbolDemodulate(observed,'QPSK',1);
        reference = reference./repelem(variance{1}+zeros(size(phase)),2);
        reference = reference.*(1-2*double(scrambled.Sequence));
        assert(norm(rx.LLR-reference)/norm(reference)<1e-12, ...
            'QPSK reliability changed in the production control consumer.');
    end
end
ok = true;
fprintf('PASS testControlSoftDemapperIntegration: actual coded control consumer, AL 1/4/16, scalar/per-RE variance.\n');
end
