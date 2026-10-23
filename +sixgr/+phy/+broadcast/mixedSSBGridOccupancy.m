function occupied=mixedSSBGridOccupancy(ssbGrid,ssbInfo,carrier)
% Project transmitted SS/PBCH RE ownership onto a common-SCS collision mask.
% This is NOT a resampled signal, a channel estimate, or an INI/EVM model.
% Waveforms are composed on the native common sample clock separately.
% Frequency cells are half-open Point-A RE intervals; OFDM time intervals
% use exact 38.211 Tc ticks, including the unequal normal-CP boundaries.
validateattributes(ssbGrid,{'numeric'},{'nonempty','finite'});
ssbSCS=double(ssbInfo.SSBTiming.SSBSubcarrierSpacingKHz);
commonSCS=double(carrier.SubcarrierSpacing);
validation=ssbInfo.SSBGridValidation;
low=double(validation.SSBLowOffsetFromPointAHz)- ...
    double(validation.CarrierLowOffsetFromPointAHz);
step=commonSCS*1000; sourceStep=ssbSCS*1000;
nsc=12*double(carrier.NSizeGrid);
assert(low>=0 && low+size(ssbGrid,1)*sourceStep<=nsc*step, ...
    'sixgr:phy:broadcast:SSBGridOutsideCarrier', ...
    'Transmitted SS/PBCH frequency cells exceed the common carrier.');
sourceSpec=struct('SCSKHz',ssbSCS,'CyclicPrefix',"normal");
targetSpec=struct('SCSKHz',commonSCS,'CyclicPrefix',string(carrier.CyclicPrefix));
nsym=double(carrier.SymbolsPerSlot);
sourceEnd=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
    floor(size(ssbGrid,2)/14),mod(size(ssbGrid,2),14),sourceSpec);
slotTicks=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/(commonSCS/15*1000);
targetSymbols=ceil(double(sourceEnd.Ticks)/slotTicks)*nsym;
edges=zeros(1,targetSymbols+1,'int64');
for k=0:targetSymbols
    t=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor(k/nsym),mod(k,nsym),targetSpec);
    edges(k+1)=t.Ticks;
end
occupied=false(nsc,targetSymbols);
source=any(ssbGrid~=0,3);
for symbol1=find(any(source,1))
    symbol0=symbol1-1;
    first=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor(symbol0/14),mod(symbol0,14),sourceSpec);
    last=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor((symbol0+1)/14),mod(symbol0+1,14),sourceSpec);
    columns=find(edges(1:end-1)<last.Ticks & edges(2:end)>first.Ticks);
    rows=zeros(0,1);
    for sourceK=reshape(find(source(:,symbol1))-1,1,[])
        firstK=floor((low+sourceK*sourceStep)/step);
        lastK=ceil((low+(sourceK+1)*sourceStep)/step)-1;
        rows=[rows;(firstK:lastK).'+1]; %#ok<AGROW>
    end
    occupied(unique(rows),columns)=true;
end
end
