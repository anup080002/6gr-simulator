function ok=testNRSLIVEncoding()
% TS 38.214 5.1.2.1 / 6.1.2.1: radix 14 also with extended CP.
% Independent numeric anchors, not encoder-versus-itself expectations.
setup6GRSimToolkit('Verbose',false);
encode=@sixgr.phy.frame.ResourceAllocationValidator.encodeSLIV;
decode=@sixgr.phy.frame.ResourceAllocationValidator.decodeSLIV;
anchors=[0 14 14 27; 2 12 14 53; 0 12 12 55; ...
    2 10 12 81; 4 8 12 102; 10 2 12 24; 11 1 12 11; ...
    0 13 14 41; 0 10 14 83];
for k=1:size(anchors,1)
    row=anchors(k,:);
    actual=encode(row(1),row(2),row(3));
    assert(actual==row(4),'NR SLIV S=%d L=%d symbols=%d: got %d expected %d.', ...
        row(1),row(2),row(3),actual,row(4));
    [s,l]=decode(row(4),row(3));
    assert(isequal([s l],row(1:2)));
end
% All geometrically valid allocations; mapping-type/DM-RS legality is
% an additional channel-specific constraint, not a change of SLIV radix.
for n=[12 14]
    values=[];
    for s=0:n-1
        for l=1:n-s
            expected=14*(l-1)+s;
            if l>8, expected=14*(15-l)+13-s; end
            assert(encode(s,l,n)==expected);
            [ds,dl]=decode(expected,n);
            assert(isequal([ds dl],[s l]));
            values(end+1)=expected; %#ok<AGROW>
        end
    end
    assert(numel(unique(values))==n*(n+1)/2);
    for code=setdiff(0:127,values)
        reject(@()decode(code,n),'sixgr:phy:frame:InvalidSLIV');
    end
end
reject(@()encode(0,14,12),'sixgr:phy:frame:InvalidTDRA');
reject(@()decode(27,12),'sixgr:phy:frame:InvalidSLIV');
reject(@()encode(0,1,13),'sixgr:phy:frame:InvalidSymbolsPerSlot');
reject(@()decode(0,13),'sixgr:phy:frame:InvalidSymbolsPerSlot');
tdra=sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
    struct('SLIV',55,'MappingType','A'),12);
assert(isequal([tdra.StartSymbol tdra.NumSymbols],[0 12]));
reject(@()sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
    struct('SLIV',55,'StartSymbol',2,'NumSymbols',10),12), ...
    'sixgr:phy:frame:InconsistentTDRA');
ok=true;
fprintf('NR_SLIV_PASS normal=105 extended=78 independent_anchors=9\n');
end

function reject(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),'Unexpected error: %s',e.identifier); return; end
error('test:MissingError','Expected %s.',id);
end
