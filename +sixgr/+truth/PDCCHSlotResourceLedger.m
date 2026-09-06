classdef PDCCHSlotResourceLedger
%PDCCHSLOTRESOURCELEDGER Value-owned reservations across DL/UL control passes.
% Both DL assignments and UL grants occupy the downlink control grid. Search
% space/CORESET identifiers do not isolate physically overlapping REs.
methods (Static)
    function [ledger, coordinates] = lookup(ledger, slot, cellID, carrier)
        validateattributes(slot, {'numeric'}, ...
            {'real','finite','integer','scalar','positive'});
        validateattributes(cellID, {'numeric'}, ...
            {'real','finite','integer','scalar','positive'});
        if isempty(ledger) || (isstruct(ledger) && isempty(fieldnames(ledger)))
            ledger = struct('Slot', double(slot), 'Entries', ...
                repmat(struct('CellID',0,'SCS',0,'CP',"", ...
                'Coordinates',zeros(0,2)),0,1));
        end
        if slot < ledger.Slot
            error('sixgr:truth:PDCCHReservationTimeReversal', ...
                'Control slot %d precedes reservation slot %d.', slot, ledger.Slot);
        elseif slot > ledger.Slot
            ledger.Slot = double(slot);
            ledger.Entries = ledger.Entries([]);
        end
        coordinates = zeros(0,2);
        index = find([ledger.Entries.CellID] == cellID, 1);
        if isempty(index)
            return;
        end
        entry = ledger.Entries(index);
        if entry.SCS ~= carrier.SubcarrierSpacing || entry.CP ~= string(carrier.CyclicPrefix)
            error('sixgr:truth:PDCCHReservationNumerologyMismatch', ...
                ['Shared-cell control reservations require a common numerology; ' ...
                 'cross-numerology time/frequency overlap must be resolved explicitly.']);
        end
        coordinates = entry.Coordinates;
    end

    function ledger = reserve(ledger, slot, cellID, carrier, coordinates)
        validateattributes(coordinates, {'numeric'}, ...
            {'real','finite','integer','nonnegative','2d','ncols',2,'nonempty'});
        [ledger, occupied] = sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
            ledger, slot, cellID, carrier);
        if size(unique(coordinates,'rows'),1) ~= size(coordinates,1) || ...
                ~isempty(intersect(occupied, coordinates, 'rows'))
            error('sixgr:truth:PDCCHResourceCollision', ...
                'PDCCH data/DM-RS resources are already reserved in slot %d, cell %d.', ...
                slot, cellID);
        end
        index = find([ledger.Entries.CellID] == cellID, 1);
        entry = struct('CellID',double(cellID), ...
            'SCS',double(carrier.SubcarrierSpacing), ...
            'CP',string(carrier.CyclicPrefix), ...
            'Coordinates',[occupied; double(coordinates)]);
        if isempty(index)
            ledger.Entries(end+1,1) = entry;
        else
            ledger.Entries(index) = entry;
        end
    end
end
end
