function ok=testSystemMultiCellFeedback()
% Production channel/feedback/reservations with numerical TEST-ONLY BLER.
% Neither this fixture nor its outcomes qualify physical UCI or study curves.
overlay='simulator/configs/validation/sls_two_cell_feedback_fixture.yaml';
assert(testSystemFTP3CalibratedDelivery("DL","network","dedicated", ...
    "per_cell_frequency_pool",overlay));
assert(testSystemFTP3CalibratedDelivery("UL","network","automatic", ...
    "per_cell_frequency_pool",overlay));
ok=true;
end
