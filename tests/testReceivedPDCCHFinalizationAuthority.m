function ok=testReceivedPDCCHFinalizationAuthority()
% Declared control-evidence boundary; no waveform or PDCCH receiver runs.
% Exercise the production binder and row annotation, not a copied completion
% loop. The returned authority list is what actual completion restores after
% the pre-reception planning row. Generic control success must not replace
% the receiver's distinct decode, data-admission and TCI status values.
setup6GRSimToolkit('Verbose',false);
statusFields={'PDCCHReceiverDecodeOk','PDCCHDataAdmissionOk','PDCCHTCIAdmissionStatus'};
violations=strings(0,1);
count=0;
for direction=["DL","UL"]
    [prepared,received]=localDeclaredGrants(direction);
    cases={ {true,true,"declared_admitted"}, ...
        {true,false,"declared_TCI_not_admitted"}, ...
        {false,false,"declared_receiver_not_usable"} };
    for k=1:numel(cases)
        values=cases{k};
        received.PDCCHReceiverDecodeOk=values{1};
        received.PDCCHDataAdmissionOk=values{2};
        received.PDCCHTCIAdmissionStatus=values{3};
        beforeRNG=rng;
        [bound,fields]=sixgr.truth.bindReceivedPDCCHGrantEvidence(prepared,received);
        assert(isequal(rng,beforeRNG),'test:PDCCHBindingExecutedRandomness', ...
            'Metadata binding must not create a new receiver realization.');
        missing=setdiff(statusFields,fields);
        if ~isempty(missing)
            violations(end+1,1)=direction+"/returned_authority/"+strjoin(string(missing),","); %#ok<AGROW>
        end
        for name=string(statusFields)
            if ~isequaln(bound.(name),received.(name))
                violations(end+1,1)=direction+"/bound/"+name; %#ok<AGROW>
            end
        end
        assert(isequal(bound.PrecodingMatrix,prepared.PrecodingMatrix) && ...
            bound.TBSBits==prepared.TBSBits && bound.MCS==prepared.MCS, ...
            'test:PDCCHBindingChangedTransmission','Received status cannot replace immutable transmission operands.');
        planned=localPlanningRow();
        % Use the real annotator for both inputs. Select ONLY the binder's
        % returned authority, not arbitrary fields retained from prepared.
        trial=table(17,NaN,false,'VariableNames',{'Slot','CRCPass','CRCApplicable'});
        trial=sixgr.truth.SharedDataCompletionRuntime.annotateGrantRows(trial,planned);
        authority=rmfield(bound,setdiff(fieldnames(bound),fields));
        out=sixgr.truth.SharedDataCompletionRuntime.annotateGrantRows( ...
            trial,struct2table(authority,'AsArray',true));
        if ~isequaln(double(out.PDCCHReceiverDecodeOk),double(received.PDCCHReceiverDecodeOk)) || ...
                ~isequaln(double(out.PDCCHDataAdmissionOk),double(received.PDCCHDataAdmissionOk)) || ...
                string(out.PDCCHTCIAdmissionStatus)~=string(received.PDCCHTCIAdmissionStatus)
            violations(end+1,1)=direction+"/final_status_projection/case"+k; %#ok<AGROW>
        end
        assert(isnan(out.CRCPass) && ~out.CRCApplicable && ~ismember('TBSBits',out.Properties.VariableNames), ...
            'test:PDCCHStatusManufacturedDataOutcome','Control metadata cannot manufacture a data CRC or grant TBS.');
        count=count+1;
    end

    % Prepared/scheduler-only status is not received authority. An older
    % receiver record may remain explicitly unqualified or be rejected; it
    % must not obtain these statuses from the prepared grant.
    absent=rmfield(received,statusFields);
    try
        [bound,fields]=sixgr.truth.bindReceivedPDCCHGrantEvidence(prepared,absent);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence'), ...
            'test:UnexpectedMissingStatusError','Unexpected missing-status rejection: %s',cause.identifier);
        fields={}; bound=struct();
    end
    assert(isempty(intersect(statusFields,fields)), ...
        'test:PlanningStatusPromotedToReceivedAuthority','A prepared status is not receiver evidence.');
    if ~isempty(fields)
        authority=rmfield(bound,setdiff(fieldnames(bound),fields));
        out=sixgr.truth.SharedDataCompletionRuntime.annotateGrantRows( ...
            localPlanningRow(),struct2table(authority,'AsArray',true));
        assert(isnan(out.PDCCHReceiverDecodeOk) && isnan(out.PDCCHDataAdmissionOk) && ...
            strlength(out.PDCCHTCIAdmissionStatus)==0, ...
            'test:PlanningStatusPromotedToReceivedAuthority','Missing receiver statuses must stay unavailable.');
    end
    wrong=received; wrong.ControlDecodeOk=false;
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(prepared,wrong), ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence');
    wrong=rmfield(received,'DCICrcPass');
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(prepared,wrong), ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence');
    wrong=received; wrong.RNTI=received.RNTI+1;
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(prepared,wrong), ...
        'sixgr:truth:ReceivedPDCCHGrantIdentityMismatch');
end
assert(isempty(violations),'test:ReceivedPDCCHFinalizationAuthorityLost', ...
    'Receiver-owned status was omitted or changed: %s',char(strjoin(violations,', ')));
fprintf('RECEIVED_PDCCH_FINALIZATION_AUTHORITY_PASS cases=%d physical_qualification=0\n',count);
ok=true;
end

function [prepared,received]=localDeclaredGrants(direction)
prepared=struct('GrantContextId',"declared_control_finalization_"+direction, ...
    'UEIndex',1,'RNTI',17,'Direction',direction,'Slot',17,'Frame',2, ...
    'ControlSlot',16,'ControlAbsoluteSlot',15,'TBSBits',984,'MCS',10, ...
    'PrecodingMatrix',[1;1]/sqrt(2), ...
    'PDCCHReceiverDecodeOk',true,'PDCCHDataAdmissionOk',true, ...
    'PDCCHTCIAdmissionStatus',"prepared_only_not_received");
received=rmfield(prepared,{'TBSBits','MCS','PrecodingMatrix'});
for name=["ControlDecodeOk","DCICrcPass","PDCCHPayloadMatch", ...
        "PDCCHCausalGrantDecodeOk","PDCCHGrantBindingRequired","PDCCHGrantBindingOk"]
    prepared.(name)=true;
    received.(name)=true;
end
% Declared equality token, not a digest of any claimed received DCI bits.
received.PDCCHGrantDCIFieldsHash=string(repmat('a',1,64));
received.PDCCHGrantFieldsHash=received.PDCCHGrantDCIFieldsHash;
end

function row=localPlanningRow()
row=table(NaN,NaN,"",'VariableNames', ...
    {'PDCCHReceiverDecodeOk','PDCCHDataAdmissionOk','PDCCHTCIAdmissionStatus'});
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('test:MissingError','Expected %s.',id);
end
