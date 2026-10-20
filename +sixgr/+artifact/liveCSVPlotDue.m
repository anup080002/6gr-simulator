function due=liveCSVPlotDue(cfg,completedSlot,totalSlots,force)
% Display cadence only. Never controls primary CSVs or terminal rendering.
if nargin<4, force=false; end
interval=double(sixgr.util.structGet(cfg,'outputs.liveCSVPNGIntervalSlots',1));
validateattributes(interval,{'double'},{'scalar','finite','integer','positive'});
validateattributes(completedSlot,{'numeric'},{'scalar','finite','integer','positive'});
validateattributes(totalSlots,{'numeric'},{'scalar','finite','integer','>=',completedSlot});
validateattributes(force,{'logical'},{'scalar'});
due=force || completedSlot==1 || completedSlot==totalSlots || mod(completedSlot,interval)==0;
end
