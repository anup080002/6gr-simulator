function ok=testPRACHCorrelationKernel()
% Numerical-kernel fixtures; not over-the-air PHY qualification.
s=RandStream('mt19937ar','Seed',91027);
lengths=[1 1;2 7;17 63;257 129;1024 512];
for precision=["double","single"]
    for k=1:size(lengths,1)
        for scale=[1e-8 1 1e8]
            a=cast(scale*(randn(s,lengths(k,1),1)+1i*randn(s,lengths(k,1),1)),precision);
            b=cast(randn(s,lengths(k,2),1)+1i*randn(s,lengths(k,2),1),precision);
            expected=conv(a,flipud(conj(b)),'full');
            actual=sixgr.rach.fullWaveformCorrelation(a,b);
            assert(isequal(size(actual),size(expected)) && strcmp(class(actual),char(precision)));
            bound=64*double(eps(char(precision)))*max(1,nextpow2(numel(expected)))* ...
                norm(double(a))*norm(double(b));
            assert(max(abs(double(actual)-double(expected)))<=bound, ...
                'FFT linear correlation differs from full conv beyond floating-point roundoff.');
        end
    end
end
for pair={{[0;1;0;0],[1;0]}, {[1;NaN;3],[1;2]}, {zeros(0,1),[1;2]}}
    a=pair{1}{1}; b=pair{1}{2};
    expected=conv(a,flipud(conj(b)),'full');
    actual=sixgr.rach.fullWaveformCorrelation(a,b);
    assert(isequaln(actual,expected),'Preserve impulse lag, nonfinite and empty-input semantics.');
end
% Unequal lengths and a nonzero delay: no circular wrap or lag reindexing.
b=complex([1;2;-1;3]); a=[zeros(11,1);b;zeros(7,1)];
c=sixgr.rach.fullWaveformCorrelation(a,b); [~,index]=max(abs(c));
assert(index-numel(b)==11);
ok=true; disp('PRACH_CORRELATION_KERNEL_PASS: full linear conv parity, all lags, single/double and amplitude scaling.');
end
