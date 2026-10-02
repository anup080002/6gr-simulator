function keys = slsLoadCalibrationKey(cases)
%SLSLOADCALIBRATIONKEY Load rates are frozen within physical comparison axes.
arguments
    cases table
end
axes = ["Scenario","Population","TargetRUPercent","UETxCase","SpatialMode","PowerCase"];
if ~all(ismember(axes,string(cases.Properties.VariableNames)))
    error("sixgr:ran1ai1032:LoadCalibrationAxes","Missing physical load-calibration axes.");
end
keys = strings(height(cases),1);
for k=1:height(cases)
    identity = table2struct(cases(k,cellstr(axes)));
    keys(k)=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(identity),"UTF-8"))));
end
end
