function previewPersistedBeamMeasurement(runRoot,outputRoot)
% Post-run analysis of persisted PHY observations, never a replacement run.
assert(~isfolder(outputRoot),'test:PreviewExists','Use a new preview folder.');
source=fullfile(runRoot,'air_interface','csv','pbch_trials.csv');
assert(isfile(source),'test:MissingPBCHSource','Canonical PBCH observations are required.');
T=readtable(source,'TextType','string','VariableNamingRule','preserve');
assert(~isempty(T) && all(ismember({'UEIndex','Slot','SSBIndex','SS_RSRP_dBm','PostEqSINR_dB'},T.Properties.VariableNames)));
mkdir(outputRoot);
copyfile(source,fullfile(outputRoot,'canonical_pbch.csv'));
spec=struct('Metric',"P1SS_RSRP_dBm",'Columns',"SS_RSRP_dBm");
summary=sixgr.truth.buildBeamMeasurementSummary(T,"SSB_DL","canonical_pbch.csv",spec);
selected=sixgr.truth.buildBeamMeasurementSummary(T,"SSB_DL","canonical_pbch.csv",struct([]),true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'beam_measurement_summary.csv'),[summary;selected],'PreserveSchema',true);
fig=figure('Visible','off','Color','white','Position',[100 100 1150 620]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(1,2);
axes1=nexttile; hold(axes1,'on');
axes2=nexttile; hold(axes2,'on');
for ue=unique(T.UEIndex(:)).'
    for beam=unique(T.SSBIndex(T.UEIndex==ue)).'
        mask=T.UEIndex==ue & T.SSBIndex==beam;
        label=sprintf('UE %g / physical SSB %g',ue,beam);
        scatter(axes1,T.Slot(mask),T.SS_RSRP_dBm(mask),55,'filled','DisplayName',label);
        scatter(axes2,T.Slot(mask),T.PostEqSINR_dB(mask),55,'filled','DisplayName',label);
    end
end
set([axes1 axes2],'Color','white','XColor','black','YColor','black','GridColor',[.5 .5 .5]);
xlabel(axes1,'Authored burst slot (CSV Slot)','Color','black'); ylabel(axes1,'Measured SS-RSRP (dBm)','Color','black');
xlabel(axes2,'Authored burst slot (CSV Slot)','Color','black'); ylabel(axes2,'Estimated post-equalization SINR (dB)','Color','black');
grid(axes1,'on'); grid(axes2,'on');
legend(axes1,'Location','best','Color','white','TextColor','black');
legend(axes2,'Location','best','Color','white','TextColor','black');
title(axes1,'Persisted per-candidate received power','Color','black');
title(axes2,'Persisted receiver estimate, not configured SNR','Color','black');
sgtitle('Post-repair analysis preview — original failed run is unchanged','Color','black');
exportgraphics(fig,fullfile(outputRoot,'beam_measurement_preview.png'),'Resolution',150);
fprintf('PERSISTED_BEAM_PREVIEW: %s; %d raw observations, %d summary rows.\n',outputRoot,height(T),height(summary)+height(selected));
end
