function [scheduled,periodicity] = csirsOccasion(cfg,absoluteSlot0)
% Shared TX/RX installed periodic resource calendar; not proof of reception.
validateattributes(absoluteSlot0,{'numeric'}, ...
    {'scalar','finite','integer','nonnegative'});
scheduled=false; periodicity="disabled";
if ~logical(sixgr.util.structGet(cfg,'phy.csirs.enable',false)), return; end
period=double(sixgr.util.structGet(cfg,'phy.csirs.period_slots',NaN));
offset=double(sixgr.util.structGet(cfg,'phy.csirs.offset_slots',NaN));
assert(isscalar(period) && isfinite(period) && period>=1 && period==round(period) && ...
    isscalar(offset) && isfinite(offset) && offset>=0 && offset<period && offset==round(offset), ...
    'sixgr:pdsch:InvalidCSIRSOccasionConfig', ...
    'Enabled CSI-RS requires integer phy.csirs.period_slots and offset_slots.');
scheduled=mod(double(absoluteSlot0)-offset,period)==0;
periodicity=string(period)+":"+string(offset);
end
