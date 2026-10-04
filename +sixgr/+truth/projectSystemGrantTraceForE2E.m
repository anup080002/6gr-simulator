function [dl,ul] = projectSystemGrantTraceForE2E(trace,nSlots,nRB)
% Preserve executed grant identity/allocation when projecting into packet replay.
validateattributes(nSlots,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(nRB,{'numeric'},{'scalar','integer','positive','finite'});
assert(istable(trace),'sixgr:e2e:InvalidGrantTrace','Expected a system grant table.');
dl=repmat({struct([])},nSlots,1); ul=dl;
if isempty(trace), return; end
required=["TTI","UE","RNTI","CellID","Direction","PRBSet","PRBCount", ...
    "PRBStart","SymbolStart","NumSymbols","TBSBits","NumLayers"];
assert(all(ismember(required,string(trace.Properties.VariableNames))), ...
    'sixgr:e2e:MissingGrantEvidence','Grant trace lacks identity or exact allocation evidence.');
for k=1:height(trace)
    row=trace(k,:);
    slot=double(row.TTI(1));
    assert(localInteger(slot,1,nSlots),'sixgr:e2e:InvalidGrantSlot', ...
        'Executed TTI must be an in-range one-based slot, not clamped into the run.');
    g=struct('UEIndex',double(row.UE(1)),'RNTI',double(row.RNTI(1)), ...
        'CellID',double(row.CellID(1)));
    assert(localInteger(g.UEIndex,1,flintmax-1)&&localInteger(g.RNTI,1,65535), ...
        'sixgr:e2e:InvalidGrantIdentity','Both internal UE and protocol RNTI are required.');
    try
        prbs=jsondecode(char(string(row.PRBSet(1))));
    catch
        error('sixgr:e2e:InvalidGrantAllocation','Exact PRBSet must be serialized numeric JSON.');
    end
    assert(isnumeric(prbs)&&isreal(prbs)&&isvector(prbs)&&~isempty(prbs), ...
        'sixgr:e2e:InvalidGrantAllocation','A grant requires its actual PRB indices.');
    prbs=double(prbs(:).');
    assert(all(isfinite(prbs)&prbs==fix(prbs)&prbs>=0&prbs<nRB)&& ...
        numel(unique(prbs))==numel(prbs)&&numel(prbs)==double(row.PRBCount(1))&& ...
        min(prbs)==double(row.PRBStart(1)), ...
        'sixgr:e2e:InvalidGrantAllocation','PRB indices, count, start and carrier bounds disagree.');
    g.PRBSet=prbs; g.NPRB=numel(prbs); g.PRBStart=double(row.PRBStart(1));
    g.SymbolAllocation=[double(row.SymbolStart(1)),double(row.NumSymbols(1))];
    assert(localInteger(g.SymbolAllocation(1),0,13)&& ...
        localInteger(g.SymbolAllocation(2),1,14)&&sum(g.SymbolAllocation)<=14, ...
        'sixgr:e2e:InvalidGrantAllocation','Executed symbol allocation is invalid.');
    g.TBSBits=double(row.TBSBits(1)); g.NumLayers=double(row.NumLayers(1));
    assert(localInteger(g.TBSBits,8,flintmax-1)&&mod(g.TBSBits,8)==0&& ...
        localInteger(g.NumLayers,1,8),'sixgr:e2e:InvalidGrantAllocation', ...
        'Real byte-aligned TBS and executed layer count must be retained.');
    g.TBSBytes=g.TBSBits/8;
    numericFields={'CQIUsed','MCSIndex','TargetCodeRate','HeadOfLineDelay_ms', ...
        'BufferBytesBefore','BufferBytesAfter','SearchSpaceID','CORESETID','BWPId','DAI','K1','K2'};
    for f=1:numel(numericFields)
        name=numericFields{f}; g.(name)=double(row.(name)(1));
    end
    g.GrantReason=string(row.GrantReason(1));
    g.HARQ=struct('HarqID',double(row.HarqID(1)),'RV',double(row.RV(1)), ...
        'NDI',double(row.NDI(1)),'IsRetransmission',logical(row.IsRetransmission(1)));
    g.CoupledAck=logical(row.Ack(1)); g.CoupledBLER=double(row.BLER(1));
    g.CoupledSINR_dB=double(row.SINR_dB(1));
    g.CoupledSource="system_waveform_grant_trace";
    direction=upper(string(row.Direction(1)));
    assert(ismember(direction,["DL","UL"]),'sixgr:e2e:InvalidGrantDirection', ...
        'An executed grant cannot be silently dropped for an unknown direction.');
    if direction=="DL"
        if isempty(dl{slot}), dl{slot}=g; else, dl{slot}(end+1,1)=g; end
    else
        if isempty(ul{slot}), ul{slot}=g; else, ul{slot}(end+1,1)=g; end
    end
end
end

function valid=localInteger(value,lower,upper)
valid=isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value)&& ...
    value==fix(value)&&value>=lower&&value<=upper;
end
