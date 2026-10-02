function bound = bindSLSFTP3Calibration(cases, rates, baseConfig)
%BINDSLSFTP3CALIBRATION Freeze measured S0 rates without releasing PHY gates.
% Use the returned Rates table or frozen_ftp3_rates.mat for byte-exact
% receipts. The sibling CSV is the human-readable audit representation.
arguments
    cases table
    rates table
    baseConfig struct
end
required=["CalibrationKey","ArrivalRatePerCell_s","TargetRUPercent", ...
    "MeasuredRUPercent","TolerancePercentagePoints","ComparatorID","Status", ...
    "CalibrationSHA256","EvidenceSHA256","PolicySHA256","BaseConfigSHA256"];
if ~all(ismember(required,string(rates.Properties.VariableNames)))
    error("sixgr:ran1ai1032:FrozenLoadSchema","Frozen rates lack measured S0 provenance.");
end
if numel(unique(string(rates.CalibrationKey)))~=height(rates)
    error("sixgr:ran1ai1032:FrozenLoadDuplicate","Exactly one frozen rate is allowed per calibration key.");
end
if any(string(rates.BaseConfigSHA256)~=localHash(baseConfig))
    error("sixgr:ran1ai1032:FrozenLoadRuntimeConfig", ...
        "Frozen load rates were measured with a different base PHY/scheduler configuration.");
end
for k=1:height(rates)
    r=rates(k,:);
    claimed=string(r.CalibrationSHA256);
    payload=removevars(r,"CalibrationSHA256");
    digest=localHash(table2struct(payload));
    if claimed~=digest || string(r.ComparatorID)~="S0" || string(r.Status)~="calibrated_measured_S0" || ...
            ~isfinite(r.ArrivalRatePerCell_s) || r.ArrivalRatePerCell_s<=0 || ...
            ~isfinite(r.MeasuredRUPercent) || r.MeasuredRUPercent<0 || r.MeasuredRUPercent>100 || ...
            ~isfinite(r.TolerancePercentagePoints) || r.TolerancePercentagePoints<=0 || ...
            abs(r.MeasuredRUPercent-r.TargetRUPercent)>r.TolerancePercentagePoints
        error("sixgr:ran1ai1032:FrozenLoadEvidence","Rate receipt digest, source, or measured target check failed.");
    end
end
keys=sixgr.studies.ran1ai1032.slsLoadCalibrationKey(cases);
[found,index]=ismember(keys,string(rates.CalibrationKey));
if any(~found)
    error("sixgr:ran1ai1032:FrozenLoadCoverage","Some physical case axes have no measured S0 rate.");
end
if ismember('PlannedExecutionArchitecture',cases.Properties.VariableNames)
    calibrated=string(cases.PlannedExecutionArchitecture)=="calibrated_link_abstraction";
    if any(calibrated)
        assert(all(ismember(["PHYExecutionMode","LinkCalibrationSHA256"], ...
            string(rates.Properties.VariableNames))), ...
            'sixgr:ran1ai1032:FrozenLoadBackend','Calibrated SLS rates require their backend and BLER dataset identity.');
        selected=rates(index(calibrated),:);
        configuredSHA=string(sixgr.util.structGet(baseConfig,'system.linkAbstraction.calibrationSHA256',''));
        assert(string(sixgr.util.structGet(baseConfig,'system.phyBackend',''))=="calibrated_link_abstraction" && ...
            strlength(configuredSHA)==64 && ...
            all(string(selected.PHYExecutionMode)=="CALIBRATED_LINK_ABSTRACTION") && ...
            all(strcmpi(string(selected.LinkCalibrationSHA256),configuredSHA)), ...
            'sixgr:ran1ai1032:FrozenLoadBackend','Do not bind waveform or differently calibrated load rates to the approved SLS backend.');
    end
end
bound=cases;
bound.PlannedConfigDeltaSHA256=cases.ConfigDeltaSHA256;
bound.FTP3ArrivalRatePerCell_s=double(rates.ArrivalRatePerCell_s(index));
bound.FTP3CalibrationSHA256=string(rates.CalibrationSHA256(index));
bound.FTP3CalibrationKey=keys;
bound.FTP3LoadStatus=repmat("measured_S0_rate_frozen",height(cases),1);
if ismember('LinkCalibrationSHA256',rates.Properties.VariableNames)
    bound.FTP3LinkCalibrationSHA256=string(rates.LinkCalibrationSHA256(index));
end
for k=1:height(bound)
    delta=bound.ConfigDelta{k};
    delta.traffic.ftp3.arrivalRatePerCell_s=bound.FTP3ArrivalRatePerCell_s(k);
    delta.traffic.ftp3.calibrationSHA256=char(bound.FTP3CalibrationSHA256(k));
    delta.traffic.arrivalRateAuthority='measured_S0_rate_frozen_across_comparators';
    bound.ConfigDelta{k}=delta;
    requiredIdentity=["CasePairKey","BasePairKey","SeedBundleID","ArrivalStreamID","ComparatorID"];
    if ~all(ismember(requiredIdentity,string(bound.Properties.VariableNames)))
        error("sixgr:ran1ai1032:FrozenLoadCaseIdentity","Case identity is incomplete for calibrated binding.");
    end
    identity=struct("CasePairKey",char(bound.CasePairKey(k)), ...
        "BasePairKey",char(bound.BasePairKey(k)), ...
        "SeedBundleID",char(bound.SeedBundleID(k)), ...
        "ArrivalStreamID",char(bound.ArrivalStreamID(k)), ...
        "ComparatorID",char(bound.ComparatorID(k)),"ConfigDelta",delta);
    bound.ConfigDeltaSHA256(k)=localHash(identity);
end
% Calibration of offered load alone is insufficient to accept an adaptive
% PHY run. Existing ExecutionStatus/PrimaryResultEligible are left intact.
end

function h=localHash(v)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(v)),"UTF-8"))));
end
