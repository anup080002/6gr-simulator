function ok=testSharedRejectedULDueHARQ()
% Actual DL TX + actual UL control rejection + scheduled PUSCH UCI RX.
% UE DL decoding intentionally unexecuted; not a missed-DCI-rate campaign.
ok=testSharedRejectedULReceiveOnly(true);
end
