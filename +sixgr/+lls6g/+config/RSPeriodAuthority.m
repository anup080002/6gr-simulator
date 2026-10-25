classdef RSPeriodAuthority
    %RSPERIODAUTHORITY Last-authored CSI-RS/TRS calendar, with explicit units.
    % Inheritance selects one authored layer, not the first alias in a merged
    % tree. Conflicting declarations within that layer fail. Conversion uses
    % the final carrier numerology; report periods on UL BWP are separate.
    methods (Static)
        function out=merge(out,authored)
            arguments
                out (1,1) struct
                authored (1,1) struct
            end
            if isempty(fieldnames(out)), out=emptyAuthority(); end
            validateAuthority(out);
            if isfield(authored,'ContractVersion')
                validateAuthority(authored);
                for name=reshape(string(fieldnames(authored.Values)),1,[])
                    out.Values.(name)=authored.Values.(name);
                end
                return;
            end
            for name=["CSIRS","TRS"]
                rows=readDeclarations(authored,name);
                if ~isempty(rows), out.Values.(name)=rows; end
            end
        end

        function cfg=apply(cfg,authority)
            arguments
                cfg (1,1) struct
                authority (1,1) struct = struct()
            end
            if isempty(fieldnames(authority)), authority=emptyAuthority(); end
            validateAuthority(authority);
            for name=["CSIRS","TRS"]
                if isfield(authority.Values,name)
                    rows=authority.Values.(name);
                else
                    rows=readDeclarations(cfg,name);
                end
                if isempty(rows), continue; end
                scs=sixgr.util.structGet(cfg,'frame.scs_khz',[]);
                assert(isnumeric(scs)&&isreal(scs)&&isscalar(scs)&&isfinite(scs)&& ...
                    ismember(double(scs),15*2.^(0:6)), ...
                    'sixgr:lls6g:config:PeriodCarrierNumerology', ...
                    'RS period aliases require the resolved NR carrier SCS.');
                perMs=double(scs)/15;
                slots=NaN;
                for k=1:numel(rows)
                    n=rows(k).Value;
                    if rows(k).Unit=="ms", n=n*perMs; end
                    assert(isfinite(n)&&n>=1&&n<=flintmax&&n==fix(n), ...
                        'sixgr:lls6g:config:NonIntegralCarrierPeriod', ...
                        '%s does not specify an exact positive carrier-slot period.',rows(k).Path);
                    assert(isnan(slots)||slots==n, ...
                        'sixgr:lls6g:config:ConflictingRSPeriodAliases', ...
                        '%s period aliases disagree in the same authored/resolved layer (%s).',name,rows(k).Path);
                    slots=n;
                end
                [paths,units]=aliases(name);
                for k=1:numel(paths)
                    value=slots;
                    if startsWith(units(k),"ms"), value=slots/perMs; end
                    if units(k)=="ms_text", value=string(value)+"ms"; end
                    if units(k)=="period_text", value=string(slots/perMs)+"ms"; end
                    % Do not invent optional aliases. Always publish the flat
                    % executed slot field, and synchronize existing mirrors.
                    if k==1||hasPath(cfg,paths(k))
                        cfg=sixgr.util.structSet(cfg,paths(k),value);
                    end
                end
            end
        end
    end
end

function a=emptyAuthority()
a=struct('ContractVersion',"sixgr.config.RSPeriodAuthority/v1",'Values',struct());
end
function validateAuthority(a)
assert(isequal(sort(fieldnames(a)),{'ContractVersion';'Values'})&& ...
    isequal(a.ContractVersion,"sixgr.config.RSPeriodAuthority/v1")&& ...
    isstruct(a.Values)&&isscalar(a.Values)&& ...
    all(ismember(string(fieldnames(a.Values)),["CSIRS","TRS"])), ...
    'sixgr:lls6g:config:InvalidRSPeriodAuthority','Invalid retained RS period authority.');
for name=reshape(string(fieldnames(a.Values)),1,[])
    rows=a.Values.(name); [paths,units]=aliases(name);
    assert(isstruct(rows)&&~isempty(rows)&& ...
        isequal(sort(fieldnames(rows)),{'Path';'Unit';'Value'}), ...
        'sixgr:lls6g:config:InvalidRSPeriodAuthority','Invalid period declaration records.');
    seen=strings(0,1);
    for row=reshape(rows,1,[])
        assert(isstring(row.Path)&&isscalar(row.Path)&&any(paths==row.Path)&& ...
            ~any(seen==row.Path),'sixgr:lls6g:config:InvalidRSPeriodAuthority', ...
            'Period paths must be distinct original supported aliases.');
        expected="slots"; if startsWith(units(paths==row.Path),"ms"), expected="ms"; end
        validUnit=isequal(row.Unit,expected);
        if units(paths==row.Path)=="period_text", validUnit=isequal(row.Unit,"slots")||isequal(row.Unit,"ms"); end
        assert(validUnit,'sixgr:lls6g:config:InvalidRSPeriodAuthority', ...
            'Retained period units must match the authored alias.');
        positive(row.Value,row.Path); seen(end+1)=row.Path; %#ok<AGROW>
    end
end
end
function rows=readDeclarations(cfg,name)
[paths,units]=aliases(name);
rows=struct('Path',{},'Unit',{},'Value',{});
for k=1:numel(paths)
    if ~hasPath(cfg,paths(k)), continue; end
    value=sixgr.util.structGet(cfg,paths(k),[]);
    parsedUnit="slots";
    if endsWith(units(k),"_text")
        assert((isstring(value)&&isscalar(value)&&~ismissing(value))|| ...
            (ischar(value)&&isrow(value)), ...
            'sixgr:lls6g:config:InvalidCarrierPeriod','%s requires a period token with its declared units.',paths(k));
        token=strtrim(string(value)); pattern='^([0-9]+(?:\.[0-9]+)?)$';
        if units(k)=="ms_text", pattern='^([0-9]+(?:\.[0-9]+)?)\s*ms$'; end
        if units(k)=="period_text"&&endsWith(token,"ms")
            pattern='^([0-9]+(?:\.[0-9]+)?)\s*ms$'; parsedUnit="ms";
        end
        parsed=regexp(char(token),pattern,'tokens','once');
        assert(~isempty(parsed),'sixgr:lls6g:config:InvalidCarrierPeriod', ...
            '%s has an invalid period token.',paths(k));
        value=str2double(parsed{1});
    end
    positive(value,paths(k)); unit="slots";
    if startsWith(units(k),"ms"), unit="ms"; end
    if units(k)=="period_text", unit=parsedUnit; end
    rows(end+1)=struct('Path',paths(k),'Unit',unit,'Value',double(value)); %#ok<AGROW>
end
end
function positive(value,path)
assert(isnumeric(value)&&~islogical(value)&&isreal(value)&&isscalar(value)&& ...
    isfinite(value)&&value>0,'sixgr:lls6g:config:InvalidCarrierPeriod', ...
    '%s requires a finite positive numeric period.',path);
if isinteger(value)
    assert(value<=cast(flintmax,'like',value), ...
        'sixgr:lls6g:config:NonIntegralCarrierPeriod','Period exceeds exact coordinate range.');
end
end
function found=hasPath(cfg,path)
found=true; value=cfg;
for key=split(path,'.').'
    if ~isstruct(value)||~isscalar(value)||~isfield(value,key), found=false; return; end
    value=value.(key);
end
end
function [paths,units]=aliases(name)
if name=="CSIRS"
    paths=["reference_signals.csi_rs_periodicity_slots", ...
        "reference_signals.nzp_csi_rs.periodicity_slots", ...
        "reference_signals.csi_rs_periodicity_ms", ...
        "reference_signals.nzp_csi_rs.periodicity_ms", ...
        "reference_signals.nzp_csi_rs.periodicity", ...
        "canonical_control.reference_signals.csi_rs_periodicity_slots", ...
        "canonical_control.reference_signals.csi_rs_periodicity_ms"];
    units=["slots","slots","ms","ms","ms_text","slots","ms"];
else
    paths=["reference_signals.trs_periodicity_slots", ...
        "reference_signals.trs.periodicity_slots", ...
        "reference_signals.trs_periodicity_ms", ...
        "reference_signals.trs.periodicity_ms", ...
        "reference_signals.trs.periodicity", ...
        "control_gating.trs_period_slots","phy.trs.period_slots", ...
        "canonical_control.reference_signals.trs_periodicity_slots", ...
        "canonical_control.reference_signals.trs_periodicity_ms"];
    units=["slots","slots","ms","ms","period_text","slots","slots","slots","ms"];
end
end
