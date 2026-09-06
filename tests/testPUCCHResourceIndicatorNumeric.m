function ok=testPUCCHResourceIndicatorNumeric()
% Independently calculated TS 38.213 v18.8.0 9.2.3 resource ordinals.
setup6GRSimToolkit('Verbose',false);
root=fullfile('tests','vectors','pucch');
v=readtable(fullfile(root,'pucch_resource_indicator_test_vectors.csv'), ...
    'Delimiter',',','NumHeaderLines',0,'ReadVariableNames',true,'TextType','string');
e=readtable(fullfile(root,'expected_pucch_resource_indicator_selection.csv'), ...
    'Delimiter',',','NumHeaderLines',0,'ReadVariableNames',true,'TextType','string');
assert(isequal(v.CaseID,e.CaseID));
for k=1:height(v)
    r=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(v(k,:));
    expectedValid=any(upper(string(e.ExpectedValid(k)))==["TRUE","1"]);
    assert(r.Valid==expectedValid);
    if r.Valid
        ordinal=str2double(string(e.ExpectedOrdinal(k)));
        assert(isfinite(ordinal) && r.Ordinal==ordinal, ...
            'PRI case %s has actual ordinal %g, expected %g.',v.CaseID(k),r.Ordinal,ordinal);
    end
end
% [R_PUCCH, PRI, n_CCE, N_CCE, one-based expected ordinal].
% Non-multiples of eight exercise both branches and their boundary.
cases=[9 0 12 24 2; 9 1 12 24 3; 9 7 23 24 9; ...
    10 1 23 24 4; 10 2 23 24 5; 15 6 23 24 14; ...
    15 7 23 24 15; 17 0 8 24 2; 17 1 8 24 4; ...
    17 7 23 24 17; 31 6 23 24 28; 31 7 23 24 31; ...
    16 7 7 8 16; 16 0 0 8 1; 16 2 8 24 5];
for k=1:size(cases,1)
    row=struct('ResourceSetID',0,'ResourceListSize',cases(k,1), ...
        'PRIFieldWidth',3,'PRIValue',cases(k,2),'FirstCCE',cases(k,3), ...
        'NumCCE',cases(k,4),'RequiresSet0CCEFormula',true);
    r=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(row);
    assert(r.Valid && r.Ordinal==cases(k,5));
end
bad=row; bad.FirstCCE=NaN;
assert(~sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(bad).Valid);
bad=row; bad.NumCCE=0;
assert(~sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(bad).Valid);
bad=row; bad.FirstCCE=bad.NumCCE;
assert(~sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(bad).Valid);
bad=row; bad.RequiresSet0CCEFormula=false;
assert(~sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(bad).Valid);
% CCE is genuinely not an operand of the direct <=8 resource mapping.
small=struct('ResourceSetID',0,'ResourceListSize',8,'PRIFieldWidth',3, ...
    'PRIValue',7,'FirstCCE',NaN,'NumCCE',NaN,'RequiresSet0CCEFormula',false);
r=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(small);
assert(r.Valid && r.Ordinal==8 && ~r.FormulaApplied);
cached=struct('PDCCHGrantFirstCCE',4,'PDCCHGrantNumCCE',24);
live=struct('PDCCHGrantFirstCCE',6,'PDCCHGrantNumCCE',8);
merged=sixgr.truth.mergeCachedGrantWithLiveRuntime(cached,live);
assert(merged.PDCCHGrantFirstCCE==6 && merged.PDCCHGrantNumCCE==8);
merged=sixgr.truth.mergeCachedGrantWithLiveRuntime(cached,struct('Slot',8));
assert(isnan(merged.PDCCHGrantFirstCCE) && isnan(merged.PDCCHGrantNumCCE));
ok=true;
disp('PUCCH_RESOURCE_INDICATOR_NUMERIC_PASS');
end
