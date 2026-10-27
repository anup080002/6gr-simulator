function reference = resolveMsg4DCIReference(cfg)
% Receiver-known CORESET0 sizing; never infer it from a transmitted grant.
reference = sixgr.phy.ra.resolveRARDCIReference(cfg);
if reference.FrequencyReferenceSource=="original_gNB_configured_mib_coreset0"
    assert(reference.AuthorityRole=="original_gNB_transmitter_configuration", ...
        'sixgr:phy:ra:MissingMsg4CORESET0','Keep original configured gNB CORESET0 authority.');
elseif startsWith(reference.FrequencyReferenceSource,"original_gNB_")
    error('sixgr:phy:ra:MissingMsg4CORESET0','TC-RNTI common DCI requires original CORESET0; no BWP substitution.');
elseif startsWith(reference.FrequencyReferenceSource,"decoded_")
    assert(reference.FrequencyReferenceSource=="decoded_mib_coreset0", ...
        'sixgr:phy:ra:MissingMsg4CORESET0','TC-RNTI DCI 1_0 requires recovered CORESET0 authority.');
else
    origin = cfg; origin.phy.carrier.NFrame=0; origin.phy.carrier.NSlot=0;
    carrier = sixgr.phy.grid.makeCarrier(origin);
    [~,~,~,type0] = sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,origin);
    reference.FrequencyReferenceSize = double(type0.CORESET0.NumRB);
    reference.FrequencyReferenceStart = double(type0.CORESET0.RBStart);
    reference.FrequencyReferenceSource = "scenario_coreset0";
end
end
