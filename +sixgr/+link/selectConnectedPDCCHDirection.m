function [rx,info]=selectConnectedPDCCHDirection(rx,info,direction)
% Dispatch already decoded connected DCIs to one directional consumer.
% No transmitted bits, resource location, grant fields or payload length
% selects a hypothesis. Preserve the complete blind result set for audit.
direction=upper(string(direction));
assert(isscalar(direction) && any(direction==["DL","UL"]) && ...
    isequal(info.ReceiverConfiguredMonitoring,true) && iscell(info.ContextValidHypotheses), ...
    'sixgr:link:InvalidConnectedDCIDispatch','Use connected blind results and a DL/UL consumer.');
hypotheses=info.ContextValidHypotheses;
selected=cell(0,1);
for k=1:numel(hypotheses)
    h=hypotheses{k};
    assert(isequal(h.Ok,true) && h.ErrFlag==0 && ...
        string(h.DCISelectionSource)=="receiver_installed_context_crc_and_semantic_parse" && ...
        isfield(h.DecodedDCI,'Direction') && ...
        any(string(h.DecodedDCI.Direction)==["DL","UL"]), ...
        'sixgr:link:InvalidConnectedDCIHypothesis','Dispatch only CRC- and context-accepted received DCIs.');
    if string(h.DecodedDCI.Direction)==direction
        selected{end+1,1}=h; %#ok<AGROW>
    end
end
[index,classification]=sixgr.phy.pdcch.reduceBlindHypotheses(selected);
info.CompositeHypothesisReductionClass=info.HypothesisReductionClass;
info.CompositeValidHypothesisCount=info.ValidHypothesisCount;
info.DirectionalConsumer=direction;
info.DirectionalSelectionSource="decoded_direction_then_payload_equivalence_no_transmit_selector";
if index>0
    rx=selected{index};
else
    % Retain the failed scalar observation for diagnostics, but no semantic
    % assignment may escape when this direction is absent or ambiguous.
    rx.Ok=false; rx.CausalGrantDecodeOk=false; rx.DecodedDCI=struct();
    rx.MissedDetection=~isempty(rx.ExpectedDCIBits);
end
rx.ValidHypothesisCount=numel(selected);
rx.HypothesisReductionClass=char(classification);
rx.MultipleEquivalentValidHypotheses=classification=="equivalent";
rx.EquivalentValidHypothesisCount=double(rx.MultipleEquivalentValidHypotheses)*numel(selected);
rx.AmbiguousValidHypotheses=classification=="ambiguous";
rx.AmbiguousHypothesisCount=double(rx.AmbiguousValidHypotheses)*numel(selected);
for name=["ValidHypothesisCount","HypothesisReductionClass", ...
        "MultipleEquivalentValidHypotheses","EquivalentValidHypothesisCount", ...
        "AmbiguousValidHypotheses","AmbiguousHypothesisCount", ...
        "DCIBitsCompared","DCIBitErrors","DCIPayloadMatch","CausalGrantDecodeOk", ...
        "FalseAlarm","MissedDetection","ReceiverHestSINR_dB","ReceiverHestSINRSource", ...
        "ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason","EVM_rms"]
    info.(name)=rx.(name);
end
info.K=rx.DCIPayloadLength;
info.DCISelectionSource=rx.DCISelectionSource;
end
