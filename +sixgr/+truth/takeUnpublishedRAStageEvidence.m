function tables = takeUnpublishedRAStageEvidence(ra, previousCount, terminal)
%TAKEUNPUBLISHEDRASTAGEEVIDENCE Publish each completed receiver stage once.
% Pending access may expose already received Msg1--4, never final-attempt
% success or a prepared future transmission. Terminal publication retains
% final summaries but excludes physical trial rows already published live.
validateattributes(previousCount,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(terminal,{'logical'},{'scalar'});
stages=sixgr.util.structGet(ra,'RuntimeStageRows',table());
assert(istable(stages) && height(stages)>=previousCount, ...
    'sixgr:truth:RAStageEvidenceRegressed','An RA continuation lost received stage rows.');
available=sixgr.util.structGet(ra,'ArtifactTables',struct());
assert(isstruct(available)&&isscalar(available), ...
    'sixgr:truth:InvalidRAStageTables','RA artifacts must be a scalar table container.');
if terminal, tables=available; else, tables=struct(); end
if isempty(stages), return; end
assert(ismember('StageName',stages.Properties.VariableNames), ...
    'sixgr:truth:MissingRAStageIdentity','Received RA stages require explicit names.');
old=string(stages.StageName(1:previousCount));
new=string(stages.StageName(previousCount+1:end));
mapping={ ...
    'Msg1', {'msg1_prach_detection','msg1_detected_candidates'}; ...
    'Msg2', {'msg2_rar_trials','msg2_pdcch_candidates','msg2_dci_fields'}; ...
    'Msg3', {'msg3_pusch_trials'}; ...
    'Msg4', {'msg4_contention_resolution','msg4_dci_fields'}};
for k=1:size(mapping,1)
    names=mapping{k,2};
    for j=1:numel(names)
        name=names{j};
        if terminal
            if any(old==mapping{k,1}) && isfield(tables,name)
                tables=rmfield(tables,name);
            end
        elseif any(new==mapping{k,1}) && isfield(available,name)
            assert(istable(available.(name)), ...
                'sixgr:truth:InvalidRAStageTable','Received stage evidence must be a table.');
            tables.(name)=available.(name);
        end
    end
end
end
