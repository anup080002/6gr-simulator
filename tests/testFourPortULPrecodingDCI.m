function ok=testFourPortULPrecodingDCI()
% TS 38.212 V18.8.0 Tables 7.3.1.1.2-2/-3, not full runtime qualification.
setup6GRSimToolkit('Verbose',false);
legacy=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'0_1');
d=legacy.Data;
d.TransformPrecodingEnabled=false;
d.ULPrecoding=struct('num_ports',4,'max_rank',4, ...
    'codebook_subset',"fullyAndPartialAndNonCoherent", ...
    'transmission_scheme',"codebook",'full_power_mode',"not_configured");
% Explicit independent rows in bit-field order, including non-monotonic ranks.
expected=[1 0;1 1;1 2;1 3;2 0;2 1;2 2;2 3;2 4;2 5;3 0;4 0; ...
    1 4;1 5;1 6;1 7;1 8;1 9;1 10;1 11;2 6;2 7;2 8;2 9;2 10;2 11;2 12;2 13; ...
    3 1;3 2;4 1;4 2;1 12;1 13;1 14;1 15;1 16;1 17;1 18;1 19; ...
    1 20;1 21;1 22;1 23;1 24;1 25;1 26;1 27;2 14;2 15;2 16;2 17; ...
    2 18;2 19;2 20;2 21;3 3;3 4;3 5;3 6;4 3;4 4];
subsets=["fullyAndPartialAndNonCoherent","partialAndNonCoherent","nonCoherent"];
counts=[62 32 12]; widths=[6 5 4]; checks=0;
for maxRank=2:4
 for subset=1:3
    d.ULPrecoding.max_rank=maxRank; d.ULPrecoding.codebook_subset=subsets(subset);
    table=sixgr.phy.pdcch.ULPrecodingField.resolve(d);
    assert(table.Width==widths(subset) && isequal(table.RankTPMI,expected(1:counts(subset),:)));
    for code=0:2^table.Width-1
        if code>=counts(subset) || expected(code+1,1)>maxRank
            localReject(@()sixgr.phy.pdcch.ULPrecodingField.decode(d,code));
            continue;
        end
        [rank,tpmi]=sixgr.phy.pdcch.ULPrecodingField.decode(d,code);
        assert(isequal([rank tpmi],expected(code+1,:)) && ...
            sixgr.phy.pdcch.ULPrecodingField.encode(d,rank,tpmi)==code);
        % Native physical precoder must exist for every accepted table row.
        [matrix,status]=sixgr.phy.ul.puschCodebookProjectionMatrix(rank,4,tpmi,false);
        assert(~isempty(matrix) && isequal(size(matrix),[4 rank]),'%s',status);
        checks=checks+1;
    end
 end
end
for subset=1:3
    d.ULPrecoding.max_rank=1; d.ULPrecoding.codebook_subset=subsets(subset);
    table=sixgr.phy.pdcch.ULPrecodingField.resolve(d);
    singleCounts=[28 12 4]; singleWidths=[5 4 2];
    assert(table.Width==singleWidths(subset));
    for code=0:singleCounts(subset)-1
        [rank,tpmi]=sixgr.phy.pdcch.ULPrecodingField.decode(d,code);
        assert(rank==1 && tpmi==code); checks=checks+1;
    end
    localReject(@()sixgr.phy.pdcch.ULPrecodingField.encode(d,2,0));
    localReject(@()sixgr.phy.pdcch.ULPrecodingField.decode(d,singleCounts(subset)));
end
fprintf('FOUR_PORT_UL_PRECODING_PASS rows=%d plus_reserved_and_max_rank_guards\n',checks);
ok=true;
end

function localReject(fn)
try, fn(); catch ME
    assert(startsWith(string(ME.identifier),'sixgr:phy:pdcch:')); return;
end
error('test:MissingRejection','An unsupported/reserved precoding request was accepted.');
end
