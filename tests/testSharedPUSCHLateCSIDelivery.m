function ok=testSharedPUSCHLateCSIDelivery()
% Actual CSI-RS measurement, HARQ/CSI-coded PUSCH, later scheduler delivery.
ok=testSharedPUSCHChannelArtifacts('TDD',true,true,true);
end
