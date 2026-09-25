function ok=testSharedCSIIMReceiver()
% Exercise muted-RE covariance capture and complex JSON through real PHY.
assert(testSharedFlatCSIRSReceiver(20,true));
assert(testSharedFlatCSIRSReceiver(-10,true));
ok=true;
end
