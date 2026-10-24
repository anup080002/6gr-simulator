function fields=ssbPowerReferenceEvidence(source)
% Copy typed same-producer power-reference evidence into existing rows.
% Empty values describe unavailable fields, never substitute trial rows.
if nargin<1, source=struct(); end
fields=struct();
defaults=sixgr.phy.refsig.buildSSBPowerMeasurementReceipt();
score=sixgr.truth.scoreSharedSSBPower();
for name=string(fieldnames(score)).'
    defaults.(name)=score.(name);
end
for name=string(fieldnames(defaults)).'
    value=sixgr.util.structGet(source,name,defaults.(name));
    if islogical(defaults.(name)), value=logical(value);
    elseif isstring(defaults.(name)), value=string(value);
    else, value=double(value);
    end
    assert(isscalar(value),'sixgr:link:SSBPowerEvidenceShape', ...
        'One original receipt/comparison value per SSB observation is required.');
    fields.(name)=value;
end
for name=["SS_RSRP_dB_re_UnitOccupiedRE_Es","SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es", ...
        "ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es","MeasuredReferenceSignalChannelGain_dB", ...
        "SSMeasurementFFTSize","ReferenceSignalTxMeasurementFFTSize", ...
        "SSPowerReferenceOffset_dB","ReferenceSignalTxPowerReferenceOffset_dB", ...
        "SSBWindowReferenceRSRQNumRB"]
    value=double(sixgr.util.structGet(source,name,NaN));
    assert(isscalar(value),'sixgr:link:SSBPowerEvidenceShape','SSB scalar power metadata must be scalar.');
    fields.(name)=value;
end
for name=["SS_RSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
        "SS_RSRPRawObservedPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
        "SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
        "ReferenceSignalTxEPREPerAntenna_dB_re_UnitOccupiedRE_Es", ...
        "SSSINRDesiredPowerPerReceiveAntenna_UnitOccupiedRE_Es", ...
        "SSSINRNoiseInterferencePowerPerReceiveAntenna_UnitOccupiedRE_Es", ...
        "SSBWindowRelativePowerMeasurementJSON","SSBWindowReferenceRSRQPerReceiveAntenna_dB", ...
        "SSBWindowReferenceRSRQScope"]
    value=string(sixgr.util.structGet(source,name,""));
    assert(isscalar(value),'sixgr:link:SSBPowerEvidenceShape','SSB vector evidence requires one token per trial.');
    fields.(name)=value;
end
end
