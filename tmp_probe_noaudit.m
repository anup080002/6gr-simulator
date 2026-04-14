setup6GRSimToolkit('Verbose',false);
out = run_6g_phy_lls_single('c:/Anup/6gsimulation/sixgr_foundation_v2 (2)/simulator/configs/scenarios/tmp_probe_noaudit.yaml','results','probe_noaudit_4slot');
sys = out.Results.System;
grants = sys.Details.SchedulerGrants;
fprintf('OK=%d\n', out.Ok);
fprintf('ServedBitsTotal=%g\n', sys.KPIs.served_bits_total);
acks = [grants.Ack];
statuses = string({grants.PHYDecisionStatus});
fprintf('DecodeOK=%g\n', sum(acks == 1));
fprintf('DecodeFail=%g\n', sum(statuses == "OK" & acks == 0));
fprintf('DecodeUnavailable=%g\n', sum(statuses == "NOT_AVAILABLE"));
idx = find(statuses == "OK");
if ~isempty(idx)
  rows = grants(idx(1:min(5,numel(idx))));
  T = struct2table(rows);
  vars = intersect({'Direction','TTI','UE','TBSBits','SINR_dB','ReceiverHestSINR_dB','DecoderTruthProxySINR_dB','Ack','BLER','PHYDecisionStatus','PHYDecisionReason'}, T.Properties.VariableNames, 'stable');
  disp(T(:, vars));
end

