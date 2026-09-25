function ok = testEVMArtifactSourceBinding(rslaSource)
% Verify plotted values, units, row counts and negative-case classification.
arguments
    rslaSource (1,1) string = ""
end
root = fileparts(fileparts(mfilename('fullpath')));
out = fullfile(root,'results','lls','evm_artifact_repair', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(out);
fig = figure('Visible','off');
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
ax = axes(fig);
data = table([901;902;903],["QPSK";"256QAM";"QPSK"], ...
    [1.25;4.75;2.5],[17.5;3.5;17.5], ...
    'VariableNames',{'CaseID','Modulation','EVM_pct','Limit_pct'});
e = sixgr.report.plotEVMByModulation(ax,data,"EVM_pct");
h = findobj(ax,'Tag','MeasuredEVM');
assert(isequal(h.YData(:),data.EVM_pct));
assert(isequal(h.XData(:),[1;2;1]));
assert(e.MeasuredPointCount==3 && e.FinitePointCount==6 && e.SeriesCount==2);
assert(string(ax.YLabel.String)=="RMS EVM (%)");
bad = data; bad.EVM_pct(2)=NaN;
localReject(@()sixgr.report.plotEVMByModulation(ax,bad,"EVM_pct"), ...
    'sixgr:report:InvalidEVMEvidence');
localReject(@()sixgr.report.plotEVMByModulation(ax,data(:,1:2),"EVM_pct"), ...
    'sixgr:report:MissingEVMEvidence');
cla(ax);
% Singleton observations must remain one point, not be padded for a gate.
e = sixgr.report.plotEVMByModulation(ax,data(1,:),"EVM_pct");
assert(e.MeasuredPointCount==1 && e.FinitePointCount==2);
% Default fixture works in a clean checkout. A retained CSV may explicitly
% be supplied for reanalysis without changing or overwriting that evidence.
if strlength(rslaSource)>0
    rsla = readtable(rslaSource,'VariableNamingRule','preserve','TextType','string');
else
    rsla = table(["a";"b";"c";"d";"e";"f"], ...
        ["DL";"UL";"DL";"UL";"DL";"UL"],repmat("gain",6,1), ...
        ["QPSK";"QPSK";"16QAM";"16QAM";"256QAM";"256QAM"], ...
        repmat("equalized_data_RE",6,1),[0;1;2;3;4;5], ...
        'VariableNames',{'CaseID','Direction','Channel','Modulation', ...
        'ReferencePoint','EVMRMSPercent'});
end
cla(ax);
e = sixgr.report.plotEVMByModulation(ax,rsla,"EVMRMSPercent");
lines = findobj(ax,'Tag','MeasuredEVM');
ys = arrayfun(@(h)h.YData(:),lines,'UniformOutput',false);
assert(isequal(sort(vertcat(ys{:})),sort(rsla.EVMRMSPercent)));
assert(e.MeasuredPointCount==height(rsla));
writetable(rsla,fullfile(out,'rsla_evm_measurements.csv'));
contract = readtable(fullfile(root,'tests','vectors','rsla','desired_rsla_image_contract.csv'), ...
    'TextType','string');
row = contract(contract.ImageFile=="rsla_evm_by_modulation.png",:);
audit = sixgr.phy.rsla.RSLAArtifactExporter.writeSemanticFigure(out,table2struct(row));
assert(audit.FinitePointCount==height(rsla));
assert(audit.XLabel=="Modulation" && audit.YLabel=="RMS EVM (%)");
insufficient = table2struct(row);
insufficient.MinimumFinitePoints = height(rsla)+1;
localReject(@()sixgr.phy.rsla.RSLAArtifactExporter.writeSemanticFigure(out,insufficient), ...
    'RSLA:IncompleteFigureSemantics');
writetable(struct2table(audit),fullfile(out,'rsla_evm_plot_audit.csv'));
fprintf('EVM_PLOT_VALUES_PASS rows=%d output=%s\n',height(rsla),out);
% Exercise the real RF evidence producer so an expected failing vector cannot
% be mistaken for a conforming transmitter in the exported row.
rfRoot = fullfile(root,'tests','vectors','rf');
rf = sixgr.rf.runtime.RFPhaseEvidenceBuilder.build(rfRoot);
t = rf.rf_evm_measurement;
assert(all(t.WithinEVMLimit == (t.EVM_pct<=t.Limit_pct)));
assert(all(t.TestPassed == (t.WithinEVMLimit==t.ExpectedWithinEVMLimit)));
assert(any(~t.WithinEVMLimit & t.TestPassed));
assert(~any(t.RequirementApplicable));
assert(all(t.EvidenceClass=="constructed_evm_measurement_unit_test"));
% Limit the exporter invocation to the repaired EVM artifact, not other RF plots.
vectorOut = fullfile(out,'contracts'); mkdir(vectorOut);
c = readtable(fullfile(rfRoot,'desired_rf_csv_contract.csv'),'TextType','string');
c = c(c.FileName=="rf_evm_measurement.csv",:);
writetable(c,fullfile(vectorOut,'desired_rf_csv_contract.csv'));
c = readtable(fullfile(rfRoot,'desired_rf_image_contract.csv'),'TextType','string');
c = c(c.ImageFile=="rf_evm_by_modulation.png",:);
writetable(c,fullfile(vectorOut,'desired_rf_image_contract.csv'));
summary = sixgr.rf.runtime.RFArtifactExporter.exportBase(rf,vectorOut,out);
assert(summary.Passed);
assert(summary.ImageAudit.FinitePointCount==2*height(t));
assert(summary.ImageAudit.YLabel=="RMS EVM (%)");
assert(contains(summary.ImageAudit.Title,"not RF conformance"));
ok = true;
fprintf('EVM_ARTIFACT_SOURCE_BINDING_PASS RF_rows=%d output=%s\n',height(t),out);
end

function localReject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error: %s',err.message);
    return
end
error('test:EVMExpectedRejection','Expected %s',id);
end
