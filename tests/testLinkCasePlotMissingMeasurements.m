function ok=testLinkCasePlotMissingMeasurements()
% A missing error-rate observation is NOT an epsilon BER/BLER measurement.
setup6GRSimToolkit('Verbose',false);
cases=["actual_zero_error";"not_measured_srs";"actual_errors"];
T=table(cases,[0;NaN;.2],[0;NaN;.1],[4;NaN;3], ...
    'VariableNames',{'Case','BLER','BER','Throughput_Mbps'});
figs=sixgr.visual.PlotLinkKPIs(struct('KPIs',struct('LinkKPI',T)),'MakeInvisible',true);
cleanup=onCleanup(@()closeFigures(figs)); %#ok<NASGU>
for name=["BLER_ByCase","BER_ByCase"]
    ax=findobj(figs.(name),'Type','axes'); data=findobj(ax,'Type','line');
    assert(numel(data)==1 && isequal(data.XData,[1 3]) && data.YData(1)==0 && ...
        data.YData(2)==T.(extractBefore(name,'_'))(3) && ax.YScale=="linear");
end
T.BLER(:)=NaN; T.BER(:)=NaN; T.Throughput_Mbps(:)=NaN;
empty=sixgr.visual.PlotLinkKPIs(struct('KPIs',struct('LinkKPI',T)),'MakeInvisible',true);
assert(~isfield(empty,'BLER_ByCase') && ~isfield(empty,'BER_ByCase') && ~isfield(empty,'Throughput_ByCase'));
T=table([0;5;10],[.2;0;NaN],[.4;.03;NaN], ...
    'VariableNames',{'SNR_dB','BLER','BLER_CI95_High'});
sweep=sixgr.visual.PlotLinkKPIs(struct('KPIs',struct('LinkSNRSweep',T)),'MakeInvisible',true);
ax=findobj(sweep.BLER,'Type','axes'); data=findobj(ax,'Type','line');
assert(ax.YScale=="linear" && all(arrayfun(@(v)isequal(v.YData,[.2 0]),data)), ...
    'Keep zero BLER, not the CI upper bound or an invented floor.');
closeFigures(sweep);
ok=true; disp('Case plots preserve measured zero and omit unavailable metrics PASS.');
end
function closeFigures(figs)
for name=string(fieldnames(figs)).'
    value=figs.(name); if isscalar(value) && isgraphics(value,'figure'), close(value); end
end
end
