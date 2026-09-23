function ok=testSSBDetectionDecision()
% Receiver-statistic test, not an integrated SSB/RF qualification campaign.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
alpha=.01; n=127;
base=sixgr.phy.sync.normalizedCorrelationDecision(.5,n,1,1,alpha,0);
assert(abs((1-base.Threshold^2)^(n-1)-alpha)<1e-14);
many=sixgr.phy.sync.normalizedCorrelationDecision(.5,n,100,4,alpha,0);
assert(many.Threshold>base.Threshold && ...
    abs(400*(1-many.Threshold^2)^(n-1)-alpha)<1e-14);
for invalid=[NaN Inf -1 1.1]
    decision=sixgr.phy.sync.normalizedCorrelationDecision(invalid,n,1,1,alpha,0);
    assert(~decision.Detected && ~decision.MetricValid);
end
floorPolicy=sixgr.phy.sync.normalizedCorrelationDecision(.5,n,1,1,alpha,.6);
assert(~floorPolicy.Detected && floorPolicy.Threshold==.6);
% The independent statistic below directly projects complex noise onto a
% fixed unit reference. It does not reuse receiver correlation code.
stream=RandStream('mt19937ar','Seed',381230);
episodes=100000; falseAlarms=0;
reference=exp(1j*(0:n-1).'*sqrt(2))/sqrt(n);
for batch=1:100
    x=complex(randn(stream,n,episodes/100),randn(stream,n,episodes/100));
    rho=abs(reference'*x)./sqrt(sum(abs(x).^2,1));
    falseAlarms=falseAlarms+nnz(rho>base.Threshold);
end
% Exact two-sided 99.9% binomial interval for this fixed-reference test.
lower=betaincinv(.0005,falseAlarms,episodes-falseAlarms+1);
upper=betaincinv(.9995,falseAlarms+1,episodes-falseAlarms);
assert(lower<alpha && upper>alpha, ...
    'test:NormalizedCorrelationNullDistribution', ...
    'Nominal alpha %.6g is outside the independent binomial interval [%.6g,%.6g].',alpha,lower,upper);
fprintf('SSB_CORRELATION_NULL_PASS episodes=%d false_alarms=%d alpha=%g CI999=[%g,%g]\n', ...
    episodes,falseAlarms,alpha,lower,upper);
ok=true;
end
