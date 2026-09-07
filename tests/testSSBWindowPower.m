function ok=testSSBWindowPower()
% Explicit known-energy unit inputs; these are not production run rows.
setup6GRSimToolkit('Verbose',false);
grid=complex(zeros(240,4,3));
for branch=1:3
    for symbol=1:4
        grid(:,symbol,branch)=sqrt(branch*symbol*1e-12);
    end
end
[m,e]=sixgr.phy.refsig.measureSSBWindowPower(grid,1,NaN,15);
expected=240*mean(1:4)*(1:3)*1e-12;
assert(max(abs(10.^((m.RSSIPerAntenna(:).'-30)/10)./expected-1))<1e-12);
assert(isequal(e.SymbolPowerPerAntenna_W,reshape(sum(abs(grid).^2,1),4,3)));
assert(e.Bandwidth_Hz==3600000 && e.NumRB==20 && ~e.CPIncluded);
[m2,e2]=sixgr.phy.refsig.measureSSBWindowPower(2*grid,1,NaN,30);
assert(max(abs(m2.RSSIPerAntenna-m.RSSIPerAntenna-20*log10(2)))<1e-10);
assert(e2.Bandwidth_Hz==2*e.Bandwidth_Hz);
% Energy added on an otherwise unallocated SSB RE MUST contribute to RSSI.
grid2=grid; grid2(1,1,1)=1e-3;
[m3,~]=sixgr.phy.refsig.measureSSBWindowPower(grid2,1,NaN,15);
assert(abs(10^((m3.RSSIPerAntenna(1)-30)/10)-(expected(1)+(1e-6-1e-12)/4))<1e-18);
assert(isequal(m3.RSSIPerAntenna(2:end),m.RSSIPerAntenna(2:end)));
try
    sixgr.phy.refsig.measureSSBWindowPower(grid(:,1:3,:),1,NaN,15);
    error('TEST:MissingWindowGuard','Incomplete SSB window accepted.');
catch ex
    assert(strcmp(ex.identifier,'sixgr:phy:refsig:InvalidSSBPowerWindow'));
end
disp('SSB_WINDOW_POWER_PASS: linear power, units, branches, bandwidth and complete window.');
ok=true;
end
