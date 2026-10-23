function ok = testNRModulationLikelihoods()
% Independent NR constellation/likelihood checks, not just TX/RX round trips.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
schemes = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
orders = [2 4 6 8 10];
rx = [0; .13+.21i; -.73+.09i; .91-.42i; -1.4-1.2i];
for s = 1:numel(schemes)
    qm = orders(s);
    labels = zeros(2^qm,qm);
    for bit = 1:qm
        labels(:,bit) = double(bitget(uint32((0:2^qm-1).'),qm-bit+1));
    end
    bits = reshape(labels.',[],1);
    reference = sixgr.pdsch.oracle.QAMMapperSpec(bits,schemes(s));
    [native,info] = sixgr.phy.mod.modulate(bits,schemes(s),'Engine','native_nr');
    assert(max(abs(native-reference))<2e-14,'Native NR constellation differs from independent oracle.');
    toolbox = nrSymbolModulate(bits,char(schemes(s)));
    assert(max(abs(native-toolbox))<2e-14,'Native NR constellation differs from MATLAB.');
    assert(abs(mean(abs(native).^2)-1)<2e-14,'Ensemble power is not one.');
    assert(info.ConstellationConvention=="TS_38_211_section_5_1");
    auto = sixgr.phy.mod.modulate(bits,schemes(s));
    assert(max(abs(auto-reference))<2e-14,'Automatic mapper changed the NR bit labels.');
    for variance = [.003 .2 3]
        [exact,exactInfo] = sixgr.phy.mod.demodulateLLR(rx,schemes(s),variance);
        [approx,approxInfo] = sixgr.phy.mod.demodulateLLR(rx,schemes(s),variance, ...
            'Engine','native_nr','Approx',true);
        % Independent full complex-alphabet posterior; no production PAM helper.
        metric = -abs(rx-reference.').^2/variance;
        refExact = zeros(numel(rx),qm);
        refApprox = refExact;
        for bit = 1:qm
            m0 = metric(:,labels(:,bit)==0); m1 = metric(:,labels(:,bit)==1);
            refExact(:,bit) = localLSE(m0)-localLSE(m1);
            refApprox(:,bit) = max(m0,[],2)-max(m1,[],2);
        end
        assert(max(abs(exact-reshape(refExact.',[],1)))<2e-10,'Exact LLR mismatch.');
        assert(max(abs(approx-reshape(refApprox.',[],1)))<2e-10,'Max-log LLR mismatch.');
        matlabLLR = nrSymbolDemodulate(rx,char(schemes(s)),variance);
        assert(max(abs(approx-matlabLLR))<2e-10,'Max-log differs from MATLAB NR.');
        assert(exactInfo.LLRAlgorithmApplied=="exact_log_sum_exp" && ~exactInfo.ApproximationApplied);
        assert(approxInfo.LLRAlgorithmApplied=="max_log" && ...
            approxInfo.ApproximationApplied==(qm>2));
        assert(exactInfo.NoiseVarUsed==variance && ~exactInfo.NoiseVarianceDefaulted);
    end
    hard = sixgr.phy.mod.demodulateLLR(native,schemes(s),1e-6);
    assert(isequal(hard<0,logical(bits)),'Noiseless hard decisions mismatch.');
end
% Repeated zeros expose the wrong cumulative pi/2 rotation after symbol 1.
bits = [0;0;0;0;1;1;1;1];
for scheme = ["BPSK","pi/2-BPSK"]
    rotation = ones(numel(bits),1);
    if scheme=="pi/2-BPSK"
        rotation(2:2:end)=1i;
    end
    expected = (1-2*bits).*(1+1i)/sqrt(2).*rotation;
    perturbed = expected + (.11-.07i);
    for engine = ["native_nr","comm","nr","auto"]
        actual = sixgr.phy.mod.modulate(bits,scheme,'Engine',engine);
        assert(max(abs(actual-expected))<2e-14,'BPSK rotation is not NR.');
        llr = sixgr.phy.mod.demodulateLLR(perturbed,scheme,.2,'Engine',engine);
        oracle = (abs(perturbed+(1+1i)/sqrt(2).*rotation).^2 ...
            - abs(perturbed-(1+1i)/sqrt(2).*rotation).^2)/.2;
        assert(max(abs(llr-oracle))<1e-12,'Binary likelihood projection is wrong.');
    end
end
[a,metadata] = sixgr.phy.mod.demodulateLLR(rx,'16QAM',[]);
b = sixgr.phy.mod.demodulateLLR(rx,'16QAM',1);
assert(isequal(a,b) && metadata.NoiseVarianceDefaulted && metadata.NoiseVarUsed==1);
assert(isempty(sixgr.phy.mod.modulate([], '16QAM','Engine','native_nr')));
assert(isempty(sixgr.phy.mod.demodulateLLR([], '16QAM',1)));
localMustError(@()sixgr.phy.mod.modulate([0;2],'QPSK'),'sixgr:phy:modulate:BadBits');
localMustError(@()sixgr.phy.mod.modulate([0;NaN],'QPSK'),'sixgr:phy:modulate:BadBits');
localMustError(@()sixgr.phy.mod.modulate([0;0],'QPSK','Engine','typo'),'sixgr:phy:modulate:BadEngine');
localMustError(@()sixgr.phy.mod.modulate(zeros(12,1),'4096QAM','Engine','nr'), ...
    'sixgr:phy:modulate:UnsupportedNRModulation');
localMustError(@()sixgr.phy.mod.modulate([0;0],'QPSK','Engine','nr','UnitAveragePower',false), ...
    'sixgr:phy:modulate:NonNRMappingOption');
for badVariance = {0, -1, Inf, [1 NaN], 1i}
    localMustError(@()sixgr.phy.mod.demodulateLLR(rx,'QPSK',badVariance{1}), ...
        'sixgr:phy:demodulateLLR:BadNoiseVar');
end
localMustError(@()sixgr.phy.mod.demodulateLLR(rx,'BAD',1),'sixgr:phy:demodulateLLR:BadMod');
localMustError(@()sixgr.phy.mod.demodulateLLR(rx,'QPSK',1,'Engine','typo'), ...
    'sixgr:phy:demodulateLLR:BadEngine');
ok = true;
fprintf('PASS testNRModulationLikelihoods: exhaustive NR labels, exact/max-log posteriors, binary rotation and negative guards.\n');
end

function out = localLSE(x)
peak = max(x,[],2);
out = peak+log(sum(exp(x-peak),2));
end

function localMustError(fun,id)
try
    fun();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error %s instead of %s.',err.identifier,id);
    return;
end
error('testNRModulationLikelihoods:MissingError','Expected %s.',id);
end
