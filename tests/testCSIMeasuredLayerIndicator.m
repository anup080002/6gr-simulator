function ok=testCSIMeasuredLayerIndicator()
% Analytic receiver-evidence fixtures, never primary campaign measurements.
[li,e]=sixgr.phy.mimo.selectCSILayerIndicator([20 1; 10 3],9);
assert(li==0 && isequal(e.MeanLinearSINRPerLayer,[15 2]));
assert(~e.ConfiguredRankShortcutUsed && e.ResourceCount==2);
assert(sixgr.phy.mimo.selectCSILayerIndicator([1 20;3 10],9)==1);
assert(sixgr.phy.mimo.selectCSILayerIndicator([2 2],9)==0);
assert(sixgr.phy.mimo.selectCSILayerIndicator([2;3],9)==0);
assert(sixgr.phy.mimo.selectCSILayerIndicator([10 1 50 2],9)==2);
localReject(@()sixgr.phy.mimo.selectCSILayerIndicator([1 NaN],9), ...
    'sixgr:mimo:MissingLayerMeasurement');
localReject(@()sixgr.phy.mimo.selectCSILayerIndicator([-1 2],9), ...
    'sixgr:mimo:MissingLayerMeasurement');
localReject(@()sixgr.phy.mimo.selectCSILayerIndicator(ones(2,5),[9 8]), ...
    'sixgr:mimo:MissingLayerMeasurement');
localReject(@()sixgr.phy.mimo.selectCSILayerIndicator(ones(2,2),[9 8]), ...
    'sixgr:mimo:MissingCodewordCQI');
% Independent direct-filter SINR closes the error-covariance calculation.
H=[1 .5i;.4 2]; W=eye(2)/sqrt(2); R=[.2 .03;.03 .1];
actual=sixgr.phy.mimo.measurePrecoderLayerSINR(H,W,R);
G=H*W; F=(G'* (R\G)+eye(2))\(G'/R); B=F*G;
expected=zeros(1,2);
for layer=1:2
    desired=abs(B(layer,layer))^2;
    interference=sum(abs(B(layer,setdiff(1:2,layer))).^2);
    noise=real(F(layer,:)*R*F(layer,:)');
    expected(layer)=desired/(interference+noise);
end
assert(max(abs(actual-expected))<1e-12);
assert(isequal(sixgr.phy.mimo.measurePrecoderLayerSINR(zeros(2),W,R),[0 0]));
ok=true;
end

function localReject(call,identifier)
try, call(); catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected error: %s',cause.message);
    return;
end
error('test:MissingError','Invalid layer evidence was accepted.');
end
