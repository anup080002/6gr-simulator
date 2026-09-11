function ok=testReceivedSINRApplicability()
% Metadata fixtures only; actual received-PDCCH coverage is tested separately.
row=struct('ReceiverHestSINR_dB',12.3,'ReceiverHestSINRValueStatus',"OK", ...
    'ReceiverHestSINRSource',"fixture_pdcch_dmrs",'ChannelEstimateAvailable',true, ...
    'ReceiverHestSINRApplicable',false,'CRCPass',0,'StrictOk',false);
bound=sixgr.truth.bindReceiverSINRApplicability(row);
assert(bound.ReceiverHestSINRApplicable && ~bound.StrictOk && bound.CRCPass==0);
assert(isequaln(rmfield(bound,'ReceiverHestSINRApplicable'), ...
    rmfield(row,'ReceiverHestSINRApplicable')));
for field=["ChannelEstimateAvailable","ReceiverHestSINR_dB","ReceiverHestSINRValueStatus"]
    unavailable=row;
    if field=="ChannelEstimateAvailable", unavailable.(field)=false;
    elseif field=="ReceiverHestSINR_dB", unavailable.(field)=NaN;
    else, unavailable.(field)="NOT_AVAILABLE"; end
    bound=sixgr.truth.bindReceiverSINRApplicability(unavailable);
    assert(~bound.ReceiverHestSINRApplicable);
    % Inconsistent evidence remains visible to the semantic auditor.
    assert(isequaln(rmfield(bound,'ReceiverHestSINRApplicable'), ...
        rmfield(unavailable,'ReceiverHestSINRApplicable')));
end
ok=true;
end
