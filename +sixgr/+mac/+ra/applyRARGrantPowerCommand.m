function pc = applyRARGrantPowerCommand(pc, grant)
% Apply the receiver-decoded RAR TPC to the existing Msg3 open-loop budget.
% This does not manufacture a budget when pathloss/power inputs are missing.
command = double(grant.TPCCommand);
if ~isscalar(command) || ~isfinite(command) || command ~= fix(command) || command < 0 || command > 7
    error("sixgr:mac:ra:InvalidRARULGrant", "Decoded RAR TPC command must be in [0,7].");
end
correction = 2*command-6; % TS 38.213 table 8.2-2, not connected-mode TPC.
oldCorrection = pc.Msg3ClosedLoopCorrection_dB;
oldCount = pc.Msg3NumPRBForPower;
pc.Msg3ClosedLoopCorrection_dB = correction;
pc.Msg3NumPRBForPower = double(grant.NumPRB);
pc.Msg3TPCCommand = command;
pc.Msg3TPCSource = "decoded_rar_table_8_2_2";
if isfinite(pc.Msg3RequestedTxPower_dBm)
    pc.Msg3RequestedTxPower_dBm = pc.Msg3RequestedTxPower_dBm - oldCorrection + ...
        correction + 10*log10(double(grant.NumPRB)/oldCount);
    pc.Msg3TxPower_dBm = min(pc.Pcmax_dBm, pc.Msg3RequestedTxPower_dBm);
    pc.Msg3PowerHeadroom_dB = pc.Pcmax_dBm-pc.Msg3TxPower_dBm;
end
end
