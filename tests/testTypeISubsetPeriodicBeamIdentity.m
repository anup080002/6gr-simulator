function ok=testTypeISubsetPeriodicBeamIdentity()
% TS 38.214 V18.9.0 5.2.2.2.1: restriction follows the steering vector.
% Mode-2 Table -6 can express v(8,0)=v(0,0) for N1=2,O1=4.
% This independent algebra check is not a native-toolbox agreement claim:
% R2026a's raw unwrapped bitmap lookup treats that boundary differently.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
request=struct('Ports',4,'N1',2,'N2',1,'O1',4,'O2',1, ...
    'Rank',2,'CodebookMode',2);
restricted=request;
restricted.CodebookSubsetRestriction=[0 0 1 1 1 1 1 1];
for phaseIndex=4:7
    baseIndex=phaseIndex-4;
    wrappedIndex=3*8+phaseIndex; % i11=3, i13=0; i2 fastest.
    Wbase=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,baseIndex);
    Wwrapped=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,wrappedIndex);
    l=floor(phaseIndex/2)+6;
    phase=mod(phaseIndex,2);
    v=[1; exp(1i*2*pi*l/8)];
    expected=[v v; exp(1i*pi*phase/2)*v -exp(1i*pi*phase/2)*v]/sqrt(8);
    assert(norm(Wbase-Wwrapped,'fro')<1e-12 && norm(Wwrapped-expected,'fro')<1e-12, ...
        'test:PeriodicBeamMismatch','Wrapped and base tuples must describe the same physical matrix.');
    for index=[baseIndex wrappedIndex]
        caught=false;
        try
            sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(restricted,index);
        catch cause
            assert(strcmp(cause.identifier,'sixgr:mimo:RestrictedPMI'), ...
                'Expected RestrictedPMI, got %s.',cause.identifier);
            caught=true;
        end
        assert(caught,'test:RestrictedBeamAlias','A duplicate PMI representation bypassed its beam restriction.');
    end
end
% A physically different allowed beam must remain selectable.
W=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(restricted,4);
assert(abs(norm(W,'fro')-1)<1e-12);
fprintf('TYPEI_SUBSET_PERIODIC_BEAM_IDENTITY_PASS alias_pairs=4 excluded_indices=8 native_boundary_equivalence_claim=0 waveform_executed=0\n');
ok=true;
end
