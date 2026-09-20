function profile=resolveConnectedMCS(root,index)
% CP-OFDM connected table semantics, including modulation-only HARQ entries.
% A reserved target code rate is not a valid new-TB MCS and is never guessed.
validateattributes(index,{'double'},{'scalar','integer','>=',0,'<=',31});
definition=sixgr.phy.research.resolveExperimentalMCSTable(root.mcsTable);
if ~isempty(definition)
    assert(isequaln(sixgr.util.structGet(root,'experimentalMCSTable',[]),definition), ...
        'sixgr:research:MCSTableContextMismatch', ...
        'Experimental codepoint contents must match the installed table definition.');
end
profile=sixgr.link.resolveMCSProfile(root.mcsTable,index);
profile.RequiresHARQHistory=false;
if profile.Valid, return; end
assert(~logical(sixgr.util.structGet(root,'transformPrecoding',false)), ...
    'sixgr:phy:pdcch:ConnectedTransformMCSUnqualified', ...
    'Transform-precoded connected HARQ requires its own MCS table qualification.');
switch lower(string(root.mcsTable))
    case {"qam64_table1","qam64lowse_table3"}
        indexes=29:31; modulations=["QPSK","16QAM","64QAM"]; qm=[2 4 6];
    case "qam256_table2"
        indexes=28:31; modulations=["QPSK","16QAM","64QAM","256QAM"]; qm=[2 4 6 8];
    otherwise
        error('sixgr:phy:pdcch:field_out_of_range','Unsupported connected MCS table.');
end
hit=find(indexes==index);
assert(isscalar(hit),'sixgr:phy:pdcch:field_out_of_range','Unknown MCS codepoint.');
profile.Modulation=modulations(hit);
profile.Qm=qm(hit);
profile.RequiresHARQHistory=true;
% Valid remains false: there is no target code rate/new-TB size in this row.
end
