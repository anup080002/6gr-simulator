function ok=testMixedSSBGridOccupancy()
% Deliberate sparse TX fixture checks time/frequency interval arithmetic.
c=nrCarrierConfig('SubcarrierSpacing',15,'NSizeGrid',106);
info.SSBTiming.SSBSubcarrierSpacingKHz=30;
info.SSBGridValidation=struct('SSBLowOffsetFromPointAHz',32*180e3+2*15e3, ...
    'CarrierLowOffsetFromPointAHz',0);
g=complex(zeros(240,28,2)); g(1,1,2)=1; g(240,28,1)=1;
mask=sixgr.phy.broadcast.mixedSSBGridOccupancy(g,info,c);
assert(isequal(size(mask),[1272 14]));
assert(all(mask(387:388,1)) && all(mask(865:866,14)) && nnz(mask)==4);
assert(~any(mask(:,2:13),'all') && ~mask(386,1) && ~mask(389,1));
% At an exactly touching symbol boundary there is no false time overlap.
g(:)=0; g(1,3,1)=1;
mask=sixgr.phy.broadcast.mixedSSBGridOccupancy(g,info,c);
assert(all(mask(387:388,2)) && nnz(mask)==2 && ~any(mask(:,1)));
ok=true; disp('MIXED_SSB_GRID_OCCUPANCY_PASS');
end
