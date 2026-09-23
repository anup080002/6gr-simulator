function ok = testPDSCHSoftDemodulationLLRSign()
%TESTPDSCHSOFTDEMODULATIONLLRSIGN Independently check the production demapper.
% Exhaustive NR mapping/sign coverage plus numerical log-MAP comparison.
% This is a demapper test, not statistical BLER or full-run qualification.

setup6GRSimToolkit("Verbose", false);
modulations = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
qmValues = [2 4 6 8 10];
checkedBits = 0;
checkedSymbols = 0;
numericalCases = 0;
maxError = 0;
snrPoints = [-30 -20 -10 0 10 20 30 40];
for index = 1:numel(modulations)
    qm = qmValues(index);
    % The former polynomial modulo-two pattern was constant: p^2+3p is
    % always even. It tested only one symbol and one bit value per QAM.
    labels = int8(dec2bin(0:2^qm-1,qm)-'0');
    bits = reshape(labels.',[],1);
    assert(all(sum(labels==0,1)==2^(qm-1)) && ...
        all(sum(labels==1,1)==2^(qm-1)), ...
        'test:MissingLLRBitCoverage','Every bit position needs both bit values.');
    symbols = sixgr.pdsch.PDSCHModulator(bits, modulations(index));
    referenceSymbols = nrSymbolModulate(bits,modulations(index));
    assert(numel(unique(symbols))==2^qm && ...
        max(abs(symbols-referenceSymbols))<1e-14 && ...
        abs(mean(abs(symbols).^2)-1)<1e-14, ...
        'test:NRConstellationMismatch', ...
        '%s must cover the complete normalized TS 38.211 constellation.',modulations(index));
    hard = sixgr.pdsch.PDSCHModulator(referenceSymbols,modulations(index), ...
        "Operation","hard-demap");
    assert(isequal(hard,bits),'Every external-reference symbol must hard-decode correctly.');
    [llr, info] = sixgr.pdsch.PDSCHModulator( ...
        symbols, modulations(index), "Operation", "soft-demap", ...
        "NoiseVariance", 1e-3, "Algorithm", "log-map");
    assert(all(isfinite(llr)) && all(llr(bits == 0) > 0) ...
        && all(llr(bits == 1) < 0), ...
        "%s production LLR signs violate positive-favours-zero.", ...
        modulations(index));
    assert(string(info.LLRConvention) == "positive_favours_bit_zero");
    checkedBits = checkedBits + numel(bits);
    checkedSymbols = checkedSymbols + numel(symbols);

    % Unit-average-energy symbols: N0=10^(-SNR/10) is the COMPLEX noise
    % variance, not variance per real component. Exercise unequal per-symbol
    % variances as used after layer-to-codeword mapping by PDSCHReceiver.
    % Off-constellation samples also distinguish log-MAP from max-log.
    observations = [-1.31+.27i; -.73-1.11i; -.19+.51i; .07-.03i; ...
        .38+.93i; .82-.44i; 1.17+1.29i; 0];
    received = repmat(observations,numel(snrPoints),1);
    n0 = repelem(10.^(-snrPoints(:)/10),numel(observations));
    exact = localReferenceLLR(received,n0,referenceSymbols,labels);
    actual = sixgr.pdsch.PDSCHModulator(received,modulations(index), ...
        "Operation","soft-demap","NoiseVariance",n0,"Algorithm","log-map");
    errorValue = max(abs(actual-exact));
    tolerance = 1e-11*max(1,max(abs(exact)));
    assert(all(isfinite(actual)) && errorValue<=tolerance, ...
        'test:LLRNumericalReferenceMismatch', ...
        '%s log-MAP differs from independent constellation likelihoods by %.12g.', ...
        modulations(index),errorValue);
    % The same inputs with scalar variance must agree with the vector path.
    for point = 1:numel(snrPoints)
        symbolRows = (point-1)*numel(observations)+(1:numel(observations));
        bitRows = (point-1)*numel(observations)*qm+(1:numel(observations)*qm);
        scalar = sixgr.pdsch.PDSCHModulator(observations,modulations(index), ...
            "Operation","soft-demap","NoiseVariance",n0(symbolRows(1)));
        assert(max(abs(scalar-actual(bitRows)))<=tolerance);
    end
    if qm>2
        approximate = sixgr.pdsch.PDSCHModulator(observations,modulations(index), ...
            "Operation","soft-demap","NoiseVariance",.5,"Algorithm","max-log");
        exactAtHalf = localReferenceLLR(observations,.5*ones(size(observations)), ...
            referenceSymbols,labels);
        assert(max(abs(approximate-exactAtHalf))>.01, ...
            'test:InsensitiveLLRReference','The numerical test must detect max-log substitution.');
    end
    numericalCases = numericalCases+numel(received);
    maxError = max(maxError,errorValue);
end
fprintf(['PDSCH_EXHAUSTIVE_LLR_REFERENCE_PASS symbols=%d bits=%d modulations=5 ' ...
    'numerical_symbol_cases=%d snr_db=%s max_abs_error=%.12g statistical_bler_qualification=0\n'], ...
    checkedSymbols,checkedBits,numericalCases,mat2str(snrPoints),maxError);
ok = true;
end

function llr = localReferenceLLR(observations,n0,points,labels)
% Public nrSymbolModulate defines the reference constellation. Evaluate
% each bit's scalar Gaussian likelihood independently of the DUT mapper,
% constellation builder, vectorized distance kernel and QPSK shortcut.
qm = size(labels,2);
values = zeros(qm,numel(observations));
for sample = 1:numel(observations)
    distance = (real(observations(sample))-real(points)).^2 + ...
        (imag(observations(sample))-imag(points)).^2;
    for bit = 1:qm
        zero = -distance(labels(:,bit)==0)/n0(sample);
        one = -distance(labels(:,bit)==1)/n0(sample);
        a = max(zero); b = max(one);
        values(bit,sample) = a-b+log(sum(exp(zero-a)))-log(sum(exp(one-b)));
    end
end
llr = values(:);
end
