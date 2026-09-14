function ok=testSharedPUCCHNoPUSCHOccasion()
% Real shared DL/SRS/absent-PUCCH reception, with UCI-on-PUSCH enabled.
% No scheduled UL command exists; UE bookkeeping is not absence authority.
root=fileparts(fileparts(mfilename('fullpath')));
output=tempname(fullfile(root,'logs'));
[ok,state]=testSharedPUCCHReceiveOnlyClock(output,fullfile(root,'simulator','configs','scenarios', ...
    'lls_pucch_gnb_no_pusch_occasion_fixture.yaml'));
assert(ok && state.CfgMobility.phy.pucch.uciOnPUSCHEnabled && numel(state.SharedGNBUCIReceptions)==1);
e=state.SharedGNBUCIReceptions{1}.TransportScheduleEvidence;
assert(e.OverlappingPUSCHCount==0 && isempty(e.NonoverlappingULControlObservationIDs) && ...
    e.Source=="physical_gNB_control_TX_ledger_not_UE_command_acceptance");
fprintf('SHARED_PUCCH_NO_PUSCH_OCCASION_PASS UCI_on_PUSCH_enabled=1 scheduled_UL_commands=0 independent_HARQ_dispositions=2 root=%s\n',output);
end
