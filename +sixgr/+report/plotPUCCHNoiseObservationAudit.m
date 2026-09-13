function plotPUCCHNoiseObservationAudit(trials,summary,path)
% Render actual noise-only diagnostic rows; never fills primary run output.
assert(istable(trials) && ~isempty(trials) && istable(summary) && ~isempty(summary));
assert(all(~trials.SignalPresent) && all(isfinite(trials.DetectionMetric)));
assert(all(summary.QualificationStatus=="component_only_no_conformance_or_ACK_miss_qualification"));
for k=1:height(summary)
    t=trials(trials.HARQBits==summary.HARQBits(k),:);
    assert(height(t)==summary.NoiseOccasions(k) && ...
        sum(t.FalseACKBits)==summary.FalseACKBits(k) && ...
        sum(t.Detected)==summary.FalseDetections(k) && ...
        summary.ACKBitDenominator(k)==height(t)*summary.HARQBits(k) && ...
        summary.DTXToACKBitFraction(k)==sum(t.FalseACKBits)/summary.ACKBitDenominator(k), ...
        'sixgr:report:PUCCHNoiseCountMismatch','Summary must match every observed trial.');
end
fig=figure('Visible','off','Color','w','Position',[100 100 1100 440]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
left=subplot(1,2,1,'Parent',fig); hold(left,'on');
labels=strings(height(summary)+1,1);
for k=1:height(summary)
    t=trials(trials.HARQBits==summary.HARQBits(k),:);
    metric=sort(t.DetectionMetric);
    stairs(left,metric,(1:numel(metric))/numel(metric),'LineWidth',1.5);
    labels(k)=string(summary.HARQBits(k))+" HARQ bit(s)";
end
threshold=unique(trials.DetectionThreshold); assert(isscalar(threshold));
xline(left,threshold,'k--','LineWidth',1.3); labels(end)="Configured threshold";
xlabel(left,'Normalized sequence correlation','Color','k'); ylabel(left,'Empirical CDF','Color','k');
title(left,'Actual noise-only detector metrics','Color','k');
legend(left,labels,'Location','southeast','Color','w','TextColor','k');
right=subplot(1,2,2,'Parent',fig);
bar(right,summary.HARQBits,100*summary.DTXToACKBitFraction);
hold(right,'on');
limit=unique(summary.Requirement); assert(isscalar(limit));
yline(right,100*limit,'k--','Reference limit','LineWidth',1.3);
xticks(right,summary.HARQBits); xlabel(right,'Configured HARQ bits per occasion','Color','k');
ylabel(right,'False ACK bits / available ACK-bit positions (%)','Color','k');
title(right,'Component observation, not conformance qualification','Color','k');
for ax=[left,right]
    set(ax,'Color','w','XColor','k','YColor','k','GridColor',[.6 .6 .6]); grid(ax,'on');
end
sgtitle(fig,sprintf('%d gNB receive branches; %d independent-noise occasions; retained RX RF', ...
    summary.ReceiveBranches(1),summary.NoiseOccasions(1)),'Color','k');
exportgraphics(fig,path,'Resolution',160);
end
