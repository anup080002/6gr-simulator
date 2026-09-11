function [wave, window] = extractTRSReceiveWindow(received, tx, slotIndex, timingOffset, resource)
%EXTRACTTRSRECEIVEWINDOW Read actual samples through the last reference symbol.
% No RX padding, boundary clamping or substitution for missing measured timing.
validateattributes(timingOffset,{'numeric'},{'scalar','real','finite','integer'});
% Use receiver-configured reference locations, including negative-test
% hypotheses, rather than borrowing the transmitter's resource placement.
assert(double(resource.Slot)==double(tx.SlotTable.Slot(slotIndex)), ...
    'sixgr:phy:trs:ReceiveSlotClockMismatch','TRS resource and received slot clocks must agree.');
carrier = resource.Carrier;
K = double(carrier.NSizeGrid)*12;
L = double(carrier.SymbolsPerSlot);
indices = double(resource.Indices(:));
validateattributes(indices,{'numeric'},{'nonempty','finite','integer','positive','<=',K*L});
requiredSymbols = max(floor((indices-1)/K))+1;
firstSymbol = (double(resource.Slot)-double(tx.FirstSlot0Based))*L;
lengths = double(tx.OFDM.SymbolLengths(:));
scale = double(tx.SampleRateHz)/(double(tx.OFDM.Nfft)*double(carrier.SubcarrierSpacing)*1000);
count = sum(lengths(firstSymbol+(1:requiredSymbols)))*scale;
if ~isfinite(count) || abs(count-round(count))>1e-7
    error('sixgr:phy:trs:InvalidReceiveSymbolClock', ...
        'TRS reference symbols must end on an exact sample boundary.');
end
count = round(count);
first = double(tx.SlotTable.StartSample1Based(slotIndex))+double(timingOffset);
last = first+count-1;
if first~=fix(first) || first<1 || last>size(received,1)
    error('sixgr:phy:trs:IncompleteReceiveWindow', ...
        'TRS requires actual received samples [%g,%g]; capture contains [1,%d].', ...
        first,last,size(received,1));
end
wave = received(first:last,:);
validateattributes(wave,{'single','double'},{'2d','nonempty','finite'});
window = struct('StartSample1Based',first,'EndSample1Based',last, ...
    'SymbolCount',requiredSymbols,'TimingOffset_samples',double(timingOffset), ...
    'Source',"measured_timing_actual_received_reference_symbol_window");
end
