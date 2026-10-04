function ok=testSLSDeferredRunnerAccounting()
% Delayed numerical fixture isolates the real runner and file ledger.
ok=testSystemFTP3CalibratedDelivery('DL','deferred_fixture');
end
