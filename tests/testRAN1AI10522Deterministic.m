function ok = testRAN1AI10522Deterministic()
%TESTRAN1AI10522DETERMINISTIC Exact placement/nesting/bundle/mapping gates.
setup6GRSimToolkit("Verbose",false);
[cfg,~,~]=sixgr.studies.ran1ai10522.loadStudyConfig( ...
    "simulator/configs/scenarios/lls_ran1_10522_td_dmrs_single_slot.yaml");
out=sixgr.studies.ran1ai10522.DeterministicSuite.run(cfg);
assert(height(out.TimeProfile)>20000 && height(out.GroupPositions)>1000);
assert(all(out.GroupPositions.GapSpread<=1));
assert(all(out.GroupPositions.FitCondition));
assert(all(out.GroupPositions.LastGroupStartsAtLMax));
expected=["0";"0|13";"0|6|13";"0|6|9|13";"0|3|6|9|13";"0|3|6|9|11|13"];
assert(isequal(string(out.NestedFamily.GroupStartSymbols),expected));
assert(all(out.NestedFamily.ExactExampleMatch));
assert(all(out.TDOCCAudit.VarianceError==0));
assert(all(out.BundleMap.CrossesRegion==false));
for region=unique(out.BundleMap.RegionId).'
    for N=unique(out.BundleMap.BundleSizePRB).'
        rows=out.BundleMap.RegionId==region & out.BundleMap.BundleSizePRB==N;
        assert(nnz(out.BundleMap.ShortenedEdgeBundle(rows))<=1);
    end
end
assert(all(out.CWLayerMapping.RoundTripExact));
[lo0,hi0]=sixgr.studies.ran1ai10522.wilsonInterval(0,1,.95);
[lo1,hi1]=sixgr.studies.ran1ai10522.wilsonInterval(1,1,.95);
assert(lo0==0 && hi0>0 && hi0<1 && lo1>0 && lo1<1 && hi1==1);
assert(lo0<=0 && 0<=hi0 && lo1<=1 && 1<=hi1);
localAssertId(@()sixgr.studies.ran1ai10522.TimeDomainProfile.resolve( ...
    struct("NSym",4,"X",2,"FirstOffsetSymbols",1,"L",2)), ...
    "sixgr:ran1ai10522:ProfileDoesNotFit");
localAssertId(@()sixgr.studies.ran1ai10522.FrequencyStructure.interleave( ...
    out.BundleMap(out.BundleMap.BundleSizePRB==2,:),"bundle_cross_region",false), ...
    "sixgr:ran1ai10522:CrossRegionCapabilityRequired");
fprintf("RAN1 10.5.2.2 deterministic: %d implicit rows, %d explicit group rows, all exact gates pass.\n", ...
    height(out.TimeProfile),height(out.GroupPositions));
ok=true;
end

function localAssertId(f,id)
try, f(); error("test:ExpectedError","Expected %s.",id);
catch ME, assert(string(ME.identifier)==id,"Expected %s, got %s.",id,ME.identifier); end
end
