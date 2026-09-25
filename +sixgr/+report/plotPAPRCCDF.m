function h=plotPAPRCCDF(ax,T)
%PLOTPAPRCCDF Plot the exact exported populations, retaining zero exceedance.
assert(istable(T)&&all(ismember({'PAPR_dB','CCDF'},T.Properties.VariableNames)), ...
    'sixgr:report:InvalidPAPRTable','PAPR plot requires a typed CCDF table.');
if ismember('PopulationID',T.Properties.VariableNames)
    keys=string(T.PopulationID);
elseif ismember('Direction',T.Properties.VariableNames)
    keys=string(T.Direction);
else
    keys=repmat("Aggregate",height(T),1);
end
populations=unique(keys,'stable'); h=gobjects(0);
hold(ax,'on');
for p=1:numel(populations)
    take=keys==populations(p); x=double(T.PAPR_dB(take)); y=double(T.CCDF(take));
    assert(all(isfinite(x)&isfinite(y)&y>=0&y<=1), ...
        'sixgr:report:InvalidPAPRTable','Invalid CCDF coordinates.');
    [x,order]=sort(x); y=y(order);
    label=populations(p);
    if ismember('Series',T.Properties.VariableNames), label=string(T.Series(find(take,1))); end
    h(end+1)=stairs(ax,x,y,'LineWidth',1.25,'Marker','o','MarkerSize',4,'DisplayName',label); %#ok<AGROW>
end
% Zero observed exceedance is a measured zero, not an epsilon or a bound.
set(ax,'YScale','linear','Color','w','XColor','k','YColor','k');
ylim(ax,[0 1]); grid(ax,'on');
xlabel(ax,'PAPR threshold (dB)','Color','k');
ylabel(ax,'Observed fraction P(PAPR > threshold)','Color','k');
title(ax,'PAPR CCDF — separate operating-point populations','Color','k');
if ~isempty(h), legend(ax,'Location','best','Interpreter','none','TextColor','k','Color','w'); end
end
