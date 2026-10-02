function ok=testSystemAutomaticPUSCHUCI()
% Actual SLS scheduling/reservations/completion, TEST-ONLY BLER curves.
ok=testSystemFTP3CalibratedDelivery("UL","network","automatic");
fprintf('SYSTEM_AUTOMATIC_PUSCH_UCI_PASS ideal_control=1 physical_uci_qualified=0\n');
end
