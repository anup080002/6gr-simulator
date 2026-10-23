function transmissions=retainedSIB1Transmissions(tx)
% Retained SI occasions are authoritative. Legacy first-occasion aliases
% must agree with them; choosing one conflicting copy hides corrupt evidence.
% tx.Waveform is intentionally excluded: it is the entire composed broadcast,
% whereas each occasion's Waveform contains only that occasion's SIB1.
transmissions=sixgr.util.structGet(tx,'SIB1Transmissions',tx);
assert(isstruct(transmissions) && ~isempty(transmissions), ...
    'sixgr:phy:broadcast:MissingSIB1Transmissions','Retained SIB1 occasions are required.');
if ~isfield(tx,'SIB1Transmissions'), return; end
first=transmissions(1);
for name=["SIB1AbsoluteSlot","SIB1WaveformStartSample"]
    assert(isfield(tx,name) && isfield(first,name) && isequaln(tx.(name),first.(name)), ...
        'sixgr:truth:SIB1GridTimingMismatch', ...
        'First-occasion %s alias disagrees with the retained SI transmission.',name);
end
for name=["PDCCHTx","PDSCHTx","SIB1Grid"]
    assert(isfield(tx,name) && isfield(first,name) && isequaln(tx.(name),first.(name)), ...
        'sixgr:truth:CanonicalTXGridMismatch', ...
        'First-occasion %s alias disagrees with the retained SI transmission.',name);
end
for name=["SIB1Waveform","SIB1SpatialMapping","SIB1PayloadHash","SIB1Bits", ...
        "SIB1PaddedBits","SIB1TransportBlockSize","DCIPayloadHex","SampleRateHz"]
    assert(isfield(tx,name) && isfield(first,name) && isequaln(tx.(name),first.(name)), ...
        'sixgr:phy:broadcast:SIB1TransmissionAliasMismatch', ...
        'First-occasion %s alias disagrees with the retained SI transmission.',name);
end
end
