function [T, removedCount] = deduplicateObservedREAllocation(T)
%DEDUPLICATEOBSERVEDREALLOCATION Retain one row per physical TX-RE run.
%
% Runtime publishers may revisit an already observed allocation while
% refreshing live artifacts.  Metadata columns on those rows contain NaN,
% and whole-table UNIQUE does not provide the physical-identity semantics
% required here.  Identify a contiguous RE run by the same coordinates and
% allocation fields used by the strict collision audit.  Distinct channels,
% allocations and ports therefore remain visible as genuine overlaps while
% bookkeeping replay of the same physical run is removed.

if nargin < 1 || ~istable(T) || isempty(T)
    removedCount = 0;
    if nargin < 1 || ~istable(T)
        T = table();
    end
    return;
end

inputCount = height(T);
identityVariables = [ ...
    "absolute_slot", "symbol_index", "port_index", ...
    "subcarrier_start", "subcarrier_count", "direction", ...
    "channel", "allocation_id"];
if all(ismember(identityVariables, string(T.Properties.VariableNames)))
    key = strings(inputCount, numel(identityVariables));
    for variableIndex = 1:numel(identityVariables)
        value = T.(identityVariables(variableIndex));
        if isnumeric(value) || islogical(value)
            key(:, variableIndex) = compose("%.17g", double(value(:)));
        else
            key(:, variableIndex) = string(value(:));
            key(ismissing(key(:, variableIndex)), variableIndex) = "<missing>";
        end
    end
    [~, firstRows] = unique(key, "rows", "stable");
    T = T(sort(firstRows), :);
else
    % Legacy/debug callers without the exact-coordinate schema retain the
    % prior conservative behavior.  Such tables cannot be promoted to the
    % primary exact-RE artifact by its schema gate.
    T = unique(T, "rows", "stable");
end
removedCount = inputCount - height(T);
end
