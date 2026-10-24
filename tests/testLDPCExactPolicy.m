function ok=testLDPCExactPolicy()
% Actual encoded-LLR component comparison with the installed native API.
% Shared native dependency: not independent BLER, RF or PHY qualification.
% No existing DL/UL caller integration or MEX equivalence is claimed here.
setup6GRSimToolkit('Verbose',false);
old=rng; restore=onCleanup(@() rng(old)); %#ok<NASGU>
rng(20261023,'twister');
algorithms=["Belief propagation","Layered belief propagation", ...
    "Normalized min-sum","Offset min-sum"];
cases=0; fullParityRows=0;
for bgn=[1 2]
    if bgn==1, K=22*32; else, K=10*32; end
    bits=int8(randi([0 1],K,3));
    encoded=nrLDPCEncode(bits,bgn);
    noisy=2*(1-2*double(encoded))+3*randn(size(encoded));
    for algorithm=algorithms
        for termination=["early","max"]
            args={'Algorithm',char(algorithm),'Termination',char(termination)};
            if algorithm=="Normalized min-sum", args=[args,{'ScalingFactor',0.61}]; end
            if algorithm=="Offset min-sum", args=[args,{'Offset',0.31}]; end
            [expected,expectedIterations,expectedParity]=nrLDPCDecode(noisy,bgn,4,args{:});
            [actual,iterations,parity,receipt]=sixgr.phy.phycode.decodeLDPCExact( ...
                noisy,bgn,4,'Algorithm',algorithm,'Termination',termination, ...
                'ScalingFactor',0.61,'Offset',0.31);
            assert(isequal(actual,expected)&&isequal(iterations,expectedIterations)&& ...
                isequal(parity,expectedParity),'test:LDPCExactMismatch', ...
                'Exact native comparison failed for BG%d %s %s.',bgn,algorithm,termination);
            assert(receipt.AppliedAlgorithm==algorithm && receipt.AppliedTermination==termination && ...
                receipt.CodeBlockCount==3 && isequal(receipt.FinalParityCheckShape,double(size(expectedParity))) && ...
                isequal(receipt.UnsatisfiedParityChecksPerCodeBlock,sum(expectedParity~=0,1)) && ...
                isequal(receipt.AllParityChecksSatisfiedPerCodeBlock,all(expectedParity==0,1)) && ...
                ~receipt.AlgorithmSubstitutionApplied && ~receipt.RetryApplied && ~receipt.MEXApplied && ...
                ~receipt.TransportBlockAcceptanceDetermined && isempty(receipt.DefaultedOptions));
            if algorithm=="Normalized min-sum"
                assert(receipt.AppliedScalingFactor==0.61 && isnan(receipt.AppliedOffset));
            elseif algorithm=="Offset min-sum"
                assert(receipt.AppliedOffset==0.31 && isnan(receipt.AppliedScalingFactor));
            else
                assert(isnan(receipt.AppliedScalingFactor)&&isnan(receipt.AppliedOffset));
            end
            if termination=="max", assert(all(iterations==4)); end
            assert(size(parity,1)>1,'Full parity must not collapse to a single head bit.');
            policy=struct('algorithm',char(algorithm),'scalingFactor',0.61, ...
                'minSumOffset',0.31,'termination',char(termination));
            for batch=[false true]
                [bd,bi,bp,br]=sixgr.phy.phycode.decodeLDPCConfigured(noisy,bgn,4,policy,batch);
                assert(isequal(bd,expected)&&isequal(bi(:),expectedIterations(:))&&isequal(bp,expectedParity));
                assert(br.AccelerationRequested==batch && ~br.MEXApplied && ...
                    br.AppliedAlgorithm==algorithm && br.AppliedTermination==termination);
            end
            fullParityRows=fullParityRows+size(parity,1); cases=cases+1;
        end
    end
    % Explicit max-iteration operation must not be silently early-terminated.
    clean=20*(1-2*double(encoded));
    [d,early,p]=sixgr.phy.phycode.decodeLDPCExact(clean,bgn,6);
    [dm,maximum,pm]=sixgr.phy.phycode.decodeLDPCExact(clean,bgn,6,'Termination','max');
    assert(isequal(d,bits)&&isequal(dm,bits)&&all(early<6)&&all(maximum==6) && ...
        all(p==0,'all')&&all(pm==0,'all'));
    % Native default is BP, unlike the simulator's explicit configured NMS.
    [native,ni,np]=nrLDPCDecode(noisy,bgn,4);
    [implicit,ii,ip,r]=sixgr.phy.phycode.decodeLDPCExact(noisy,bgn,4);
    assert(isequal(implicit,native)&&isequal(ii,ni)&&isequal(ip,np)&&r.AppliedAlgorithm=="Belief propagation" && ...
        all(ismember(["Algorithm","ScalingFactor","Offset","Termination"],r.DefaultedOptions)));
    singleLLR=single(noisy(:,1));
    [native,ni,np]=nrLDPCDecode(singleLLR,bgn,4,'Algorithm','Normalized min-sum');
    [actual,ai,ap,r]=sixgr.phy.phycode.decodeLDPCExact(singleLLR,bgn,4,'Algorithm','Normalized min-sum');
    assert(isequal(actual,native)&&isequal(ai,ni)&&isequal(ap,np)&&r.InputLLRClass=="single");
    cases=cases+3;
end
for algorithm=["unknown","Normalized","Offset","Layered"]
    reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'Algorithm',algorithm));
end
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'Algorithm',["Belief propagation","Offset min-sum"]));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'Termination','unknown'));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'ScalingFactor',0));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'ScalingFactor',1.1));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'Offset',-1));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'Offset',Inf));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4.5));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,3,4));
reject(@()sixgr.phy.phycode.decodeLDPCExact(noisy,2,4,'EarlyTermination',true));
bad=noisy; bad(1)=NaN; reject(@()sixgr.phy.phycode.decodeLDPCExact(bad,2,4));
reject(@()sixgr.phy.phycode.decodeLDPCExact(complex(noisy,ones(size(noisy))),2,4));
fprintf('LDPC_EXACT_POLICY_PASS positive_cases=%d retained_parity_rows=%d shared_native_reference=1 DL_UL_integration=0 MEX_qualification=0\n', ...
    cases,fullParityRows);
ok=true;
end

function reject(f)
try
    f();
catch e
    assert(~isempty(e.identifier),'Rejection must retain an error identifier.');
    return;
end
error('test:LDPCExactMissingRejection','Invalid decoder policy/operand was accepted.');
end
