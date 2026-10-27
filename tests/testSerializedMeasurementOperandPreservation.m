function ok=testSerializedMeasurementOperandPreservation()
% Opposite-plane absence is not a display category or numeric operand.
fields=["AllocationCarrierRSSIPerReceiveAntenna_dBm", ...
    "AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
    "SSBWindowRSSIPerReceiveAntenna_dBm","MeasurementRSRPPerResource_dBm"];
T=table((1:2).','VariableNames',{'Slot'});
for f=fields, T.(f)=["";"[1,2]"]; end
T.AllocationCarrierPowerMeasurementJSON=["";"{}"];
for scope=["dl_pdsch_trials","ul_pusch_trials","pbch_trials","csi_rs_trials"]
    F=sixgr.truth.fillBlankCategoricalColumns(T,scope);
    C=sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,F);
    for f=[fields,"AllocationCarrierPowerMeasurementJSON"]
        assert(isequal(F.(f),T.(f))&&isequal(C.(f),T.(f)));
    end
end
ok=true;
fprintf('SERIALIZED_MEASUREMENT_OPERAND_PRESERVATION_PASS\n');
end
