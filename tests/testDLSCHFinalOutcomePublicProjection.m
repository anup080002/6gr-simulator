function ok=testDLSCHFinalOutcomePublicProjection()
% Declared adapter fixtures, NOT decoded PHY or statistical BLER evidence.
% The public serializer is not an independent receipt validator/producer.
setup6GRSimToolkit('Verbose',false);
source=table([7;8;9],[0;1;NaN], ...
    'VariableNames',{'Slot','CRCPass'});
source.DLSCHFinalOutcomeAvailable=[true;true;false];
source.DLSCHFinalOutcomeStage=["declared_projection_fixture";"declared_projection_fixture";""];
source.DLSCHFinalOutcomeJSON=[string(jsonencode(struct( ...
    'Scope',"declared, adapter-only fixture",'CRCPassPerCodeword',[true false]))); ...
    string(jsonencode(struct('Scope',"declared adapter-only fixture", ...
    'CRCPassPerCodeword',true))); ""];
source.DLSCHFinalOutcomeSHA256=[sixgr.util.sha256Hex(char(source.DLSCHFinalOutcomeJSON(1))); ...
    sixgr.util.sha256Hex(char(source.DLSCHFinalOutcomeJSON(2))); ""];
source.DLSCHSuccessfulDecodedBits=[40;40;NaN];
source.DLSCHSuccessfulDecodedBitsScope=["declared_attempt_fixture";"declared_attempt_fixture";""];
source.DLSCHAggregateGoodBitsPolicy=["declared_all_codewords_pass";"declared_all_codewords_pass";""];
% Separate declared shared-owner bindings. A failed CRC can have known zero
% credit; a successful CRC without an original credit receipt stays unbound.
% These adapter fixtures do not construct/validate live transport receipts.
source.SharedDLSCHOutcomeAvailable=[true;true;false];
source.SharedDLSCHOutcomeStage=["declared_shared_projection_fixture"; ...
    "declared_shared_projection_fixture";""];
source.SharedDLSCHOutcomeJSON=[string(jsonencode(struct( ...
    'Scope',"declared shared adapter-only fixture", ...
    'DecoderSHA256',source.DLSCHFinalOutcomeSHA256(1), ...
    'TransportCreditAvailable',true,'TransportCreditBits',0))); ...
    string(jsonencode(struct('Scope',"declared shared adapter-only fixture", ...
    'DecoderSHA256',source.DLSCHFinalOutcomeSHA256(2), ...
    'TransportCreditAvailable',false,'TransportCreditBits',NaN))); ""];
source.SharedDLSCHOutcomeSHA256=[sixgr.util.sha256Hex(char(source.SharedDLSCHOutcomeJSON(1))); ...
    sixgr.util.sha256Hex(char(source.SharedDLSCHOutcomeJSON(2))); ""];
source.SharedDLSCHOutcomeTransmissionID=["declared_tx_a";"declared_tx_b";""];
source.SharedDLSCHOutcomeDecoderSHA256=source.DLSCHFinalOutcomeSHA256;
source.SharedDLSCHOutcomeTransportCreditBound=[true;false;false];
source.PrivateDecoderSoftArrays=repmat({ones(3,1)},3,1);
fields=string(source.Properties.VariableNames);
fields=fields(startsWith(fields,"DLSCH")|startsWith(fields,"SharedDLSCH"));
assert(numel(fields)==14);
base=struct('pdsch_table',source,'pusch_table',source,'pdcch_dci_table',source);
meta=struct('logical_run_id',"declared_final_codeword_projection",'run_id',31);
contract=sixgr.truth.llsOutputContract();
before=base; randomBefore=rng;
out=sixgr.truth.buildLLSPublicOutputTables(base,contract,meta);
assert(isequaln(before,base)&&isequaln(randomBefore,rng));
published=out.pdsch_runtime_event_table;
assert(height(published)==height(source)&&isequal(published.Slot,source.Slot));
for name=fields
    assert(ismember(name,string(published.Properties.VariableNames))&& ...
        isequaln(published.(name),source.(name)), ...
        'Final outcome field changed during public projection: %s',name);
end
assert(~ismember('PrivateDecoderSoftArrays',published.Properties.VariableNames));
assert(published.SharedDLSCHOutcomeTransportCreditBound(1)&&source.CRCPass(1)==0&& ...
    ~published.SharedDLSCHOutcomeTransportCreditBound(2)&&source.CRCPass(2)==1);
for family=["pusch_runtime_event_table","pdcch_dci_public_table"]
    assert(~any(ismember(fields,string(out.(family).Properties.VariableNames))), ...
        'DL final-codeword evidence must not be manufactured for another channel.');
end
folder=tempname; mkdir(folder);
file=fullfile(folder,'declared_final_decoder_projection.csv');
sixgr.util.csvWriteTable(file,published,'RoundTripNumericText',true);
loaded=sixgr.util.csvReadTable(file,'TextType','string');
assert(isequal(loaded.DLSCHFinalOutcomeJSON(1:2),published.DLSCHFinalOutcomeJSON(1:2))&& ...
    isequal(loaded.DLSCHFinalOutcomeSHA256(1:2),published.DLSCHFinalOutcomeSHA256(1:2))&& ...
    isequaln(double(loaded.DLSCHSuccessfulDecodedBits),published.DLSCHSuccessfulDecodedBits));
sharedText=["SharedDLSCHOutcomeStage","SharedDLSCHOutcomeJSON", ...
    "SharedDLSCHOutcomeSHA256","SharedDLSCHOutcomeTransmissionID", ...
    "SharedDLSCHOutcomeDecoderSHA256"];
for name=sharedText
    assert(isequal(loaded.(name)(1:2),published.(name)(1:2)), ...
        'Shared binding token changed during CSV serialization: %s',name);
end
for name=["DLSCHFinalOutcomeAvailable","SharedDLSCHOutcomeAvailable", ...
        "SharedDLSCHOutcomeTransportCreditBound"]
    assert(isequal(double(loaded.(name)),double(published.(name))), ...
        'Availability/credit flag changed during CSV serialization: %s',name);
end
% CSV's empty field can import as empty text or missing text; neither may
% become a fabricated receipt/hash for the unavailable third observation.
for name=["DLSCHFinalOutcomeJSON","DLSCHFinalOutcomeSHA256",sharedText]
    value=loaded.(name)(3);
    assert(ismissing(value)||strlength(value)==0);
end
% Projection preserves supplied all-unavailable schema in memory; it does
% not create placeholders when the original columns themselves are absent.
unavailable=source(3,:);
out=sixgr.truth.buildLLSPublicOutputTables(struct('pdsch_table',unavailable),contract,meta);
for name=fields
    assert(isequaln(out.pdsch_runtime_event_table.(name),unavailable.(name)));
end
missing=removevars(source,cellstr([fields "PrivateDecoderSoftArrays"]));
out=sixgr.truth.buildLLSPublicOutputTables(struct('pdsch_table',missing),contract,meta);
assert(~any(ismember(fields,string(out.pdsch_runtime_event_table.Properties.VariableNames))));
out=sixgr.truth.buildLLSPublicOutputTables(struct(),contract,meta);
assert(isempty(out.pdsch_runtime_event_table));
fprintf('DLSCH_FINAL_PUBLIC_PROJECTION_PASS declared_rows=3 preserved_fields=14 no_PHY_or_receipt_qualification=1\n');
ok=true;
end
