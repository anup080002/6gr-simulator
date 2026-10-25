function pc = applyRARGrantPowerCommand(pc, grant)
% Apply the receiver-decoded RAR TPC to the existing Msg3 open-loop budget.
% This does not manufacture a budget when pathloss/power inputs are missing.
command = double(grant.TPCCommand);
if ~isscalar(command) || ~isfinite(command) || command ~= fix(command) || command < 0 || command > 7
    error("sixgr:mac:ra:InvalidRARULGrant", "Decoded RAR TPC command must be in [0,7].");
end
pc = sixgr.mac.ra.resolveRARPUSCHPower(pc,grant,true);
end
