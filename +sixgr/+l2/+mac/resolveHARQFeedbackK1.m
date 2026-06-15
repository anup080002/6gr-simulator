function k1 = resolveHARQFeedbackK1(pdschSlot, tddPattern, mu)
%RESOLVEHARQFEEDBACKK1 Resolve DL HARQ-ACK timing K1 from a TDD pattern.
%
% Explicit scenario HARQ timing still takes precedence in the schedulers.
% This helper only replaces the old hardcoded default when no explicit K1
% exists, using the next UL opportunity in the configured TDD pattern.

if nargin < 2 || isempty(tddPattern)
    tddPattern = "DDDSU";
end
if nargin < 3 || isempty(mu)
    mu = 1;
end
mu = max(0, round(double(mu)));
slotsPerFrame = 10 * 2^mu;
slotInFrame = mod(max(0, round(double(pdschSlot))), slotsPerFrame);
pattern = upper(strtrim(string(tddPattern)));

switch pattern
    case "DDDSU"
        ulSlots = 4:5:(slotsPerFrame - 1);
    case "DDDDDDDSUU"
        ulSlots = [];
        base = [8 9];
        for f = 0:ceil(slotsPerFrame / 10)
            ulSlots = [ulSlots, base + 10 * f]; %#ok<AGROW>
        end
        ulSlots = ulSlots(ulSlots < slotsPerFrame);
    otherwise
        chars = char(pattern);
        ulBase = find(chars == 'U') - 1;
        if isempty(ulBase)
            k1 = 4;
            return;
        end
        ulSlots = [];
        for f = 0:ceil(slotsPerFrame / max(1, numel(chars)))
            ulSlots = [ulSlots, ulBase + f * numel(chars)]; %#ok<AGROW>
        end
        ulSlots = ulSlots(ulSlots < slotsPerFrame);
end

nextUL = ulSlots(find(ulSlots > slotInFrame, 1, "first"));
if isempty(nextUL)
    nextUL = ulSlots(1) + slotsPerFrame;
end
k1 = max(1, min(16, round(double(nextUL - slotInFrame))));
end
