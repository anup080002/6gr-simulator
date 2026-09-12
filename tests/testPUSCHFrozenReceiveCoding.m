function ok=testPUSCHFrozenReceiveCoding()
setup6GRSimToolkit('Verbose',false);
opt=struct('RV',[],'TransportBlockSize',[],'TargetCodeRate',[]);
grant=struct('HARQProcessKey',struct('RV',2), ...
    'CodingLayout',struct('TBSBits',19968,'TargetCodeRate',948/1024));
actual=sixgr.phy.ul.pusch.resolveFrozenReceiveCoding(opt,grant);
assert(actual.RV==2 && actual.TransportBlockSize==19968 && actual.TargetCodeRate==948/1024);
assert(isequal(actual,sixgr.phy.ul.pusch.resolveFrozenReceiveCoding(actual,grant)));
for name=["RV","TransportBlockSize","TargetCodeRate"]
    wrong=actual; wrong.(name)=actual.(name)+1;
    localReject(@()sixgr.phy.ul.pusch.resolveFrozenReceiveCoding(wrong,grant), ...
        'sixgr:phy:ul:PUSCHFrozenReceiveCodingMismatch');
end
missing=grant; missing.HARQProcessKey.RV=NaN;
localReject(@()sixgr.phy.ul.pusch.resolveFrozenReceiveCoding(opt,missing), ...
    'sixgr:phy:ul:PUSCHFrozenReceiveCodingMissing');
disp('PUSCH_FROZEN_RECEIVE_CODING_PASS: retained gNB RV/TBS/rate and contradictory-input rejection.');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
