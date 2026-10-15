function row=bindConverterEvidence(row,rxReplay,txReplay)
% Keep executed RX ADC and TX DAC populations separate in every data row.
% Missing/disabled evidence is not a zero-clipping observation.
for prefix=["ADC","DAC"]
    replay=rxReplay; if prefix=="DAC", replay=txReplay; end
    row.(prefix+"QuantizationExecuted")=logical(sixgr.util.structGet( ...
        replay,prefix+"QuantizationExecuted",false));
    for field=["ClippingRatio","ClippedSampleCount","ClippingSampleCount"]
        row.(prefix+field)=double(sixgr.util.structGet(replay,prefix+field,NaN));
    end
    for field=["ClippingPopulation","ClippingSource","ClippingThresholdRule"]
        row.(prefix+field)=string(sixgr.util.structGet(replay,prefix+field,""));
    end
    row.(prefix+"ClippingStatus")=string(sixgr.util.structGet( ...
        replay,prefix+"ClippingStatus","unavailable_no_converter_execution_evidence"));
end
for field=["DACFullScale","DACConfiguredFullScale","DACReferenceRMS", ...
        "DACReferenceHeadroom_dB","DACReferenceREEnergy","DACReferenceNfft", ...
        "DACReferenceSubcarriers","DACReferenceTxPorts"]
    row.(field)=double(sixgr.util.structGet(txReplay,field,NaN));
end
for field=["DACReferenceDomain","DACReferenceSource"]
    row.(field)=string(sixgr.util.structGet(txReplay,field,""));
end
row.DACReferencePayloadDependent=logical(sixgr.util.structGet( ...
    txReplay,'DACReferencePayloadDependent',false));
row.ADCConventionConfigured=string(sixgr.util.structGet(rxReplay,'ADCConventionConfigured',''));
for field=["ADCDitherRMSConfigured","ADCApertureJitterSecondsConfigured", ...
        "ADCINLLSBConfigured","ADCDNLLSBConfigured","ADCSeedConfigured"]
    row.(field)=double(sixgr.util.structGet(rxReplay,field,NaN));
end
end
