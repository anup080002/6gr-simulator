function rec=normalizeReceivedSSBPowerReference(rec,cfg)
% One scale contract for full-burst acquisition and per-occasion tracking.
fixed=strcmpi(string(sixgr.util.structGet(cfg,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
    logical(sixgr.util.structGet(cfg,'integration.configured_snr_is_link_authority',false));
if ~fixed, return; end
status=string(sixgr.util.structGet(rec,'SSPhysicalMeasurementStatus',"unavailable"));
assert(~logical(sixgr.util.structGet(rec,'SSPowerReferenceNormalized',false)) && ...
    status~="available_normalized_fixed_esn0_not_absolute_dbm", ...
    'sixgr:link:SSBPowerReferenceAlreadyNormalized','Normalize received power exactly once.');
available=startsWith(status,"available");
rsrp=double(sixgr.util.structGet(rec,'SS_RSRP_dBm',NaN));
assert(isscalar(status) && (~available || (isscalar(rsrp) && isfinite(rsrp))), ...
    'sixgr:link:MissingSSBPowerMeasurement','Available SSB RSRP requires a finite actual measurement.');
nfft=double(sixgr.util.structGet(rec,'SSMeasurementFFTSize',NaN));
scale=double(sixgr.util.structGet(rec,'SSMeasurementGridScaleToSqrtW',NaN));
txNfft=double(sixgr.util.structGet(rec,'ReferenceSignalTxMeasurementFFTSize',NaN));
txScale=double(sixgr.util.structGet(rec,'ReferenceSignalTxMeasurementGridScaleToSqrtW',NaN));
numeric=["SS_RSRP","SS_RSRPRawObserved"];
textual=["SS_RSRPPerReceiveAntenna","SS_RSRPRawObservedPerReceiveAntenna", ...
    "SSBWindowRSSIPerReceiveAntenna"];
for name=numeric
    rec.(name+"_dB_re_UnitOccupiedRE_Es")=localConvert( ...
        double(sixgr.util.structGet(rec,name+"_dBm",NaN)),nfft,scale,false);
    rec.(name+"_dBm")=NaN;
end
for name=textual
    rec.(name+"_dB_re_UnitOccupiedRE_Es")=localConvert( ...
        string(sixgr.util.structGet(rec,name+"_dBm","")),nfft,scale,false);
    rec.(name+"_dBm")="";
end
rec.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es=localConvert( ...
    double(sixgr.util.structGet(rec,'ReferenceSignalTxEPRE_dBm',NaN)),txNfft,txScale,false);
rec.ReferenceSignalTxEPREPerAntenna_dB_re_UnitOccupiedRE_Es=localConvert( ...
    string(sixgr.util.structGet(rec,'ReferenceSignalTxEPREPerAntenna_dBm',"")),txNfft,txScale,false);
rec.ReferenceSignalTxEPRE_dBm=NaN;
rec.ReferenceSignalTxEPREPerAntenna_dBm="";
for name=["SSSINRDesiredPowerPerReceiveAntenna","SSSINRNoiseInterferencePowerPerReceiveAntenna"]
    rec.(name+"_UnitOccupiedRE_Es")=localConvert( ...
        string(sixgr.util.structGet(rec,name+"_W","")),nfft,scale,true);
    rec.(name+"_W")="";
end
rec.SSPowerReferenceOffset_dB=localOffset(nfft,scale);
rec.ReferenceSignalTxPowerReferenceOffset_dB=localOffset(txNfft,txScale);
rec.SSMeasurementGridScaleToSqrtW=NaN;
rec.ReferenceSignalTxMeasurementGridScaleToSqrtW=NaN;
rec.MeasuredReferenceSignalChannelGain_dB= ...
    rec.SS_RSRP_dB_re_UnitOccupiedRE_Es-rec.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es;
rec.SSBWindowPowerMeasurementJSON=""; % Its schema declares dBm, unavailable here.
rec.SSSTxPowerDeltaFromSignalled_dB=NaN;
rec.MeasuredReferenceSignalPathloss_dB=NaN;
rec.MeasuredReferenceSignalPathlossSource="unavailable_normalized_fixed_esn0_has_no_absolute_link_budget";
if isfinite(rec.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es)
    source=string(sixgr.util.structGet(rec,'ReferenceSignalTxMeasurementSource',""));
    assert(isscalar(source) && strlength(strtrim(source))>0, ...
        'sixgr:link:MissingSSBTxPowerSource','Do not claim measured TX EPRE without its producer source.');
    rec.ReferenceSignalTxMeasurementSource=source+"_relative_to_unit_occupied_re_es";
end
rec.PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es";
rec.SSPowerReferenceNormalized=true;
if available
    rec.SSPhysicalMeasurementStatus="available_normalized_fixed_esn0_not_absolute_dbm";
end
end

function offset=localOffset(nfft,scale)
valid=isscalar(nfft) && isreal(nfft) && isfinite(nfft) && nfft>=1 && nfft==fix(nfft) && ...
    isscalar(scale) && isreal(scale) && isfinite(scale) && ...
    abs(scale-nfft*sqrt(1000))<=16*eps(nfft*sqrt(1000));
offset=NaN;
if valid, offset=20*log10(nfft); end
end

function result=localConvert(value,nfft,scale,linear)
% dBm from grid/(Nfft*sqrt(1000)) needs +20*log10(Nfft).
% Linear watt-domain operands need scale^2. Neither operation touches IQ.
textual=~isnumeric(value); delimiter="|"; bracketed=false;
if textual
    value=strtrim(string(value));
    assert(isscalar(value) && ~ismissing(value),'sixgr:link:InvalidSSBPowerToken','Expected one numeric SSB power token.');
    if value=="", result=value; return; end
    bracketed=startsWith(value,"[") && endsWith(value,"]");
    assert(~xor(startsWith(value,"["),endsWith(value,"]")), ...
        'sixgr:link:InvalidSSBPowerToken','SSB power brackets must be balanced.');
    if bracketed
        if strlength(value)==2, result="[]"; return; end
        value=strtrim(extractBetween(value,2,strlength(value)-1));
        delimiter=",";
    elseif contains(value,";"), delimiter=";";
    end
    if value=="", result="[]"; return; end
    assert(isempty(regexp(char(value),'(^[,;|]|[,;|]$|[,;|]\s*[,;|])','once')), ...
        'sixgr:link:InvalidSSBPowerToken','Do not collapse a missing SSB power-vector element.');
    parts=regexp(char(value),'[\s,;|]+','split');
    value=str2double(parts);
    assert(all(~isnan(value) | strcmpi(parts,'NaN')), ...
        'sixgr:link:InvalidSSBPowerToken','Malformed SSB powers must not become missing measurements.');
end
offset=localOffset(nfft,scale);
assert(isreal(value) && (all(isnan(value),'all') || isfinite(offset)), ...
    'sixgr:link:MissingSSBPowerScale','Retained SSB power requires its actual producer FFT size and matching grid scale.');
if linear
    assert(all(value>=0 | isnan(value),'all'),'sixgr:link:InvalidSSBLinearPower','Signal and disturbance powers cannot be negative.');
    result=value*scale^2;
else
    result=value+offset;
end
if textual
    result=strjoin(compose('%.15g',result),delimiter);
    if bracketed, result="["+result+"]"; end
end
end
