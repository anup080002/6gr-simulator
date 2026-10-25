classdef CSIReportPeriodAuthority
    %CSIREPORTPERIODAUTHORITY Authored report calendar, in the reporting UL BWP.
    % TS 38.214 V18.8.0 5.2.1.4: reportSlotConfig uses UL-BWP slots.
    % Period and offset have independent last-author ownership. The retained
    % declaration capsule distinguishes authored milliseconds from resolved
    % slot mirrors after serialization or an SCS-only sweep. It is config
    % provenance, not received RRC or evidence of a transmitted report.
    methods (Static)
        function out=merge(out,authored)
            if isempty(fieldnames(out)), out=emptyAuthority(); end
            out=validateAuthority(out);
            if isfield(authored,'ContractVersion')
                next=validateAuthority(authored);
            elseif has(authored,capsulePath())
                next=readCapsule(authored,struct());
            else
                next=emptyAuthority();
                for name=["Period","Offset"]
                    rows=declarations(authored,name);
                    if ~isempty(rows), next.Values.(name)=rows; end
                end
            end
            for name=reshape(string(fieldnames(next.Values)),1,[])
                out.Values.(name)=next.Values.(name);
            end
        end

        function authority=capture(cfg,authored)
            % An explicit sweep author may change its exact paths. Other
            % mirrors of a serialized calendar must still match its receipt.
            if nargin<2, authored=struct(); end
            if has(cfg,capsulePath())
                authority=readCapsule(cfg,authored);
            else
                authority=sixgr.lls6g.config.CSIReportPeriodAuthority.merge(struct(),cfg);
            end
            authority=sixgr.lls6g.config.CSIReportPeriodAuthority.merge(authority,authored);
        end

        function cfg=apply(cfg,authority)
            if nargin<2 || isempty(fieldnames(authority))
                authority=sixgr.lls6g.config.CSIReportPeriodAuthority.capture(cfg);
            end
            authority=validateAuthority(authority);
            for name=["Period","Offset"]
                if ~isfield(authority.Values,name)
                    rows=declarations(cfg,name);
                    assert(~isempty(rows),'sixgr:lls6g:config:MissingCSIReportCalendar', ...
                        'CSI report %s requires its own configured declaration, not the CSI-RS calendar.',name);
                    authority.Values.(name)=rows;
                end
            end
            clock=scenarioClock(cfg);
            [period,offset]=resolve(authority.Values,clock.SCSKHz);
            cfg=publish(cfg,period,offset,clock.SCSKHz);
            receipt=struct('ContractVersion',"sixgr.config.CSIReportCalendar/v2", ...
                'Declarations',authority.Values,'Clock',clock, ...
                'PeriodSlots',period,'OffsetSlots',offset);
            receipt.SHA256=sixgr.lls6g.config.hashResolvedScenario(receipt);
            cfg=sixgr.util.structSet(cfg,capsulePath(),receipt);
        end

        function clock=installedClock(cfg)
            % Read the original typed frame snapshot, not a carrier fallback.
            id=sixgr.util.structGet(cfg,'phy.frame.DefaultIdentity',struct());
            carriers=sixgr.util.structGet(cfg,'phy.frame.ComponentCarriers',struct([]));
            assert(isstruct(id)&&isscalar(id)&&all(isfield(id,{'ScheduledCCID','ULBWPID'}))&& ...
                isstruct(carriers)&&~isempty(carriers)&&all(isfield(carriers,{'CCID','BWPs'})), ...
                'sixgr:lls6g:config:CSIReportULBWPClock','An installed report UL carrier/BWP is required.');
            integer(id.ScheduledCCID,0); integer(id.ULBWPID,0);
            selected=find([carriers.CCID]==id.ScheduledCCID);
            assert(isscalar(selected),'sixgr:lls6g:config:CSIReportULBWPClock','Report carrier must be installed exactly once.');
            bwps=carriers(selected).BWPs;
            selected=find([bwps.BWPID]==id.ULBWPID & upper(string({bwps.Direction}))=="UL");
            assert(isscalar(selected),'sixgr:lls6g:config:CSIReportULBWPClock','Report UL BWP must be installed exactly once.');
            bwp=bwps(selected); scs(bwp.SCSKHz);
            clock=struct('CCID',double(id.ScheduledCCID),'BWPID',double(id.ULBWPID), ...
                'SCSKHz',double(bwp.SCSKHz));
        end

        function cfg=bind(cfg,scenario)
            receipt=sixgr.util.structGet(scenario,capsulePath(),struct());
            readCapsule(scenario,struct());
            clock=sixgr.lls6g.config.CSIReportPeriodAuthority.installedClock(cfg);
            assert(isequaln(clock,receipt.Clock), ...
                'sixgr:lls6g:config:CSIReportULBWPClock', ...
                'Resolved CSI-report clock does not match the installed UL BWP.');
            cfg.phy.csi.reportPeriodicitySlots=receipt.PeriodSlots;
            cfg.phy.csi.reportOffsetSlots=receipt.OffsetSlots;
            cfg.phy.csi.reportCalendarClock=clock;
            cfg.phy.csi.reportCalendarAuthority=receipt;
        end
    end
end

function path=capsulePath()
path="csi_acquisition_and_reporting.report_calendar_authority";
end
function a=emptyAuthority()
a=struct('ContractVersion',"sixgr.config.CSIReportPeriodAuthority/v1",'Values',struct());
end
function a=validateAuthority(a)
assert(isstruct(a)&&isscalar(a)&&isequal(sort(fieldnames(a)),{'ContractVersion';'Values'})&& ...
    textEqual(a.ContractVersion,"sixgr.config.CSIReportPeriodAuthority/v1")&& ...
    isstruct(a.Values)&&isscalar(a.Values)&&all(ismember(string(fieldnames(a.Values)),["Period","Offset"])), ...
    'sixgr:lls6g:config:InvalidCSIReportAuthority','Invalid CSI-report declaration authority.');
a.ContractVersion=string(a.ContractVersion);
values=struct();
for name=["Period","Offset"]
    if ~isfield(a.Values,name), continue; end
    rows=a.Values.(name); [paths,units]=aliases(name);
    assert(isstruct(rows)&&~isempty(rows)&&isequal(sort(fieldnames(rows)),{'Path';'Unit';'Value'}), ...
        'sixgr:lls6g:config:InvalidCSIReportAuthority','Invalid report declaration records.');
    normalized=struct('Path',{},'Unit',{},'Value',{}); seen=strings(0,1);
    for row=reshape(rows,1,[])
        assert(textScalar(row.Path)&&textScalar(row.Unit), ...
            'sixgr:lls6g:config:InvalidCSIReportAuthority','Declaration paths and units must be scalar text.');
        path=string(row.Path); unit=string(row.Unit); k=find(paths==path);
        assert(isscalar(k)&&~any(seen==path)&&unit==units(k), ...
            'sixgr:lls6g:config:InvalidCSIReportAuthority','Unknown, duplicate or unit-mismatched report declaration.');
        numeric(row.Value,0);
        assert(name~="Period"||row.Value>0,'sixgr:lls6g:config:InvalidCSIReportPeriod','Report period must be positive.');
        if unit=="slots", integer(row.Value,double(name=="Period")); end
        normalized(end+1)=struct('Path',path,'Unit',unit,'Value',double(row.Value)); %#ok<AGROW>
        seen(end+1)=path; %#ok<AGROW>
    end
    values.(name)=normalized;
end
a.Values=values;
end
function a=readCapsule(cfg,authored)
r=sixgr.util.structGet(cfg,capsulePath(),struct());
assert(isstruct(r)&&isscalar(r)&&isequal(sort(fieldnames(r)), ...
    {'Clock';'ContractVersion';'Declarations';'OffsetSlots';'PeriodSlots';'SHA256'})&& ...
    (textEqual(r.ContractVersion,"sixgr.config.CSIReportCalendar/v1")|| ...
     textEqual(r.ContractVersion,"sixgr.config.CSIReportCalendar/v2")), ...
    'sixgr:lls6g:config:InvalidCSIReportAuthority','Malformed resolved CSI-report provenance.');
a=validateAuthority(struct('ContractVersion',"sixgr.config.CSIReportPeriodAuthority/v1",'Values',r.Declarations));
assert(all(isfield(a.Values,{'Period','Offset'}))&&isstruct(r.Clock)&&isscalar(r.Clock)&& ...
    isequal(sort(fieldnames(r.Clock)),{'BWPID';'CCID';'SCSKHz'}), ...
    'sixgr:lls6g:config:InvalidCSIReportAuthority','Incomplete CSI-report clock/declarations.');
integer(r.Clock.CCID,0); integer(r.Clock.BWPID,0); scs(r.Clock.SCSKHz);
clock=struct('CCID',double(r.Clock.CCID),'BWPID',double(r.Clock.BWPID),'SCSKHz',double(r.Clock.SCSKHz));
[p,o]=resolve(a.Values,clock.SCSKHz);
integer(r.PeriodSlots,1); integer(r.OffsetSlots,0);
assert(r.PeriodSlots==p&&r.OffsetSlots==o, ...
    'sixgr:lls6g:config:InvalidCSIReportAuthority','Resolved period differs from original declarations.');
canonical=struct('ContractVersion',string(r.ContractVersion), ...
    'Declarations',a.Values,'Clock',clock,'PeriodSlots',p,'OffsetSlots',o);
assert(textEqual(r.SHA256,sixgr.lls6g.config.hashResolvedScenario(canonical)), ...
    'sixgr:lls6g:config:InvalidCSIReportAuthority','CSI-report declaration digest changed.');
expected=publish(struct(),p,o,clock.SCSKHz);
for name=["Period","Offset"]
    [paths,~]=aliases(name);
    for path=paths
        if has(authored,path), continue; end
        % v1 did not publish canonical-control mirrors. Validate any that
        % were present, but do not invent historical authorship on reload.
        if textEqual(r.ContractVersion,"sixgr.config.CSIReportCalendar/v1")&& ...
                startsWith(path,"canonical_control.")&&~has(cfg,path)
            continue;
        end
        assert(has(cfg,path),'sixgr:lls6g:config:CSIReportAliasChanged','A resolved CSI-report mirror is missing: %s.',path);
        got=declarationsForPath(cfg,path,name); want=declarationsForPath(expected,path,name);
        assert(got.Value==want.Value&&got.Unit==want.Unit, ...
            'sixgr:lls6g:config:CSIReportAliasChanged','CSI-report mirror %s changed without an authored override.',path);
    end
end
end
function cfg=publish(cfg,p,o,scsKHz)
cfg=sixgr.util.structSet(cfg,'csi_acquisition_and_reporting.csi_report_periodicity_slots',p);
cfg=sixgr.util.structSet(cfg,'reference_signals.csi_report_periodicity_slots',p);
cfg=sixgr.util.structSet(cfg,'csi_acquisition_and_reporting.report_periodicity',string(p/(scsKHz/15))+"ms");
cfg=sixgr.util.structSet(cfg,'csi_acquisition_and_reporting.csi_report_offset_slots',o);
cfg=sixgr.util.structSet(cfg,'reference_signals.csi_report_offset_slots',o);
cfg=sixgr.util.structSet(cfg,'canonical_control.reference_signals.csi_report_periodicity_slots',p);
cfg=sixgr.util.structSet(cfg,'canonical_control.reference_signals.csi_report_offset_slots',o);
end
function [p,o]=resolve(values,scsKHz)
p=resolveGroup(values.Period,scsKHz,1); o=resolveGroup(values.Offset,scsKHz,0);
assert(o<p,'sixgr:lls6g:config:InvalidCSIReportOffset','CSI-report offset must be smaller than its UL-BWP period.');
end
function n=resolveGroup(rows,scsKHz,minimum)
n=NaN;
for row=reshape(rows,1,[])
    value=row.Value;
    if string(row.Unit)=="ms", value=value*(scsKHz/15); end
    assert(isfinite(value)&&value>=minimum&&value<=flintmax&&value==fix(value), ...
        'sixgr:lls6g:config:NonIntegralCSIReportPeriod','%s is not an exact UL-BWP slot coordinate.',row.Path);
    assert(isnan(n)||n==value,'sixgr:lls6g:config:ConflictingCSIReportAliases', ...
        'CSI-report aliases in the same authored layer disagree (%s).',row.Path);
    n=value;
end
end
function rows=declarations(cfg,name)
[paths,~]=aliases(name); rows=struct('Path',{},'Unit',{},'Value',{});
for path=paths
    if has(cfg,path), rows(end+1)=declarationsForPath(cfg,path,name); end %#ok<AGROW>
end
end
function row=declarationsForPath(cfg,path,name)
[paths,units]=aliases(name); unit=units(paths==path);
v=sixgr.util.structGet(cfg,path,[]);
if unit=="ms"
    assert(textScalar(v),'sixgr:lls6g:config:InvalidCSIReportPeriod','%s requires an explicit millisecond token.',path);
    match=regexp(char(strtrim(string(v))),'^([0-9]+(?:\.[0-9]+)?)\s*ms$','tokens','once');
    assert(~isempty(match),'sixgr:lls6g:config:InvalidCSIReportPeriod','%s requires Nms.',path);
    v=str2double(match{1});
end
numeric(v,0);
assert(name~="Period"||v>0,'sixgr:lls6g:config:InvalidCSIReportPeriod','Report period must be positive.');
if unit=="slots", integer(v,double(name=="Period")); end
row=struct('Path',path,'Unit',unit,'Value',double(v));
end
function [paths,units]=aliases(name)
if name=="Period"
    paths=["csi_acquisition_and_reporting.csi_report_periodicity_slots", ...
        "reference_signals.csi_report_periodicity_slots","csi_acquisition_and_reporting.report_periodicity", ...
        "canonical_control.reference_signals.csi_report_periodicity_slots"];
    units=["slots","slots","ms","slots"];
else
    paths=["csi_acquisition_and_reporting.csi_report_offset_slots","reference_signals.csi_report_offset_slots", ...
        "canonical_control.reference_signals.csi_report_offset_slots"];
    units=["slots","slots","slots"];
end
end
function clock=scenarioClock(s)
% Mirror only clock/identity selection from FrameRuntimeStateBuilder. The
% builder MUST subsequently compare this with its native typed snapshot.
% No frame_timing.slot_duration_ms, run horizon or CSI-RS SCS participates.
base=sixgr.util.structGet(s,'frame.scs_khz',[]); scs(base);
ccid=0; raw=sixgr.util.structGet(s,'bwp.ul',struct([])); gridSCS=base;
carriers=sixgr.util.structGet(s,'component_carriers', ...
    sixgr.util.structGet(s,'bwp.component_carriers',struct([])));
if ~isempty(carriers)
    carriers=sequence(carriers); first=carriers{1};
    firstID=field(first,["CCID","cc_id"],0); integer(firstID,0); target=firstID;
    map=field(first,["CarrierIndicatorMap","carrier_indicator_map"],struct([]));
    if ~isempty(map)
        map=sequence(map); found=false;
        for k=1:numel(map)
            indicator=field(map{k},["Indicator","indicator"],[]); integer(indicator,0);
            if indicator==0
                assert(~found,'sixgr:lls6g:config:CSIReportULBWPClock','Ambiguous default carrier indicator.');
                target=field(map{k},["ScheduledCCID","scheduled_cc_id"],[]); integer(target,0); found=true;
            end
        end
        assert(found,'sixgr:lls6g:config:CSIReportULBWPClock','Default carrier indicator is not configured.');
    end
    hits=false(1,numel(carriers));
    for k=1:numel(carriers)
        id=field(carriers{k},["CCID","cc_id"],k-1); integer(id,0); hits(k)=id==target;
    end
    assert(nnz(hits)==1,'sixgr:lls6g:config:CSIReportULBWPClock','Report carrier is not uniquely configured.');
    carrier=carriers{find(hits)}; ccid=target;
    grid=field(carrier,["ULCarrierGrid","ul_carrier_grid"],struct());
    gridSCS=field(grid,["SubcarrierSpacingKHz","SubcarrierSpacing_kHz","SCSKHz","scs_khz"],base);
    allBWPs=field(carrier,["BWPs","bwps","BWPConfigs","bwp_configs"],struct([]));
    if ~isempty(allBWPs)
        allBWPs=sequence(allBWPs); raw={};
        for k=1:numel(allBWPs)
            fallback=""; if k==1, fallback="DL"; elseif k==2, fallback="UL"; end
            direction=upper(string(field(allBWPs{k},["Direction","direction"],fallback)));
            if direction=="UL", raw{end+1}=allBWPs{k}; end %#ok<AGROW>
        end
    else
        ul=field(carrier,["ULBWPs","ul_bwps"],struct([]));
        if ~isempty(ul), raw=ul; end
    end
end
scs(gridSCS); bwp=struct();
if ~isempty(raw)
    items=sequence(raw); active=false(1,numel(items));
    for k=1:numel(items)
        flag=field(items{k},["ActiveInitial","active_initial","Active","active"],[]);
        if isempty(flag)&&numel(items)==1, flag=true; end
        assert((islogical(flag)||isnumeric(flag))&&isreal(flag)&&isscalar(flag)&&ismember(flag,[0 1]), ...
            'sixgr:lls6g:config:CSIReportULBWPClock','Every multi-BWP entry needs an explicit initial active flag.');
        active(k)=logical(flag);
    end
    assert(nnz(active)==1,'sixgr:lls6g:config:CSIReportULBWPClock','Exactly one reporting UL BWP must be active initially.');
    bwp=items{find(active)};
end
% bwp.ul's lower-case YAML aliases are mapped before the typed builder.
id=field(bwp,["bwp_id","BWPID","id"],0); integer(id,0);
spacing=field(bwp,["scs_khz","SCSKHz","SubcarrierSpacingKHz","SubcarrierSpacing_kHz"],gridSCS); scs(spacing);
clock=struct('CCID',double(ccid),'BWPID',double(id),'SCSKHz',double(spacing));
end
function rows=sequence(raw)
if iscell(raw), rows=reshape(raw,1,[]); else, rows=num2cell(raw(:).'); end
assert(~isempty(rows)&&all(cellfun(@(x)isstruct(x)&&isscalar(x),rows)), ...
    'sixgr:lls6g:config:CSIReportULBWPClock','Carrier/BWP configurations must be scalar structs.');
end
function v=field(s,paths,fallback)
v=fallback;
for path=paths
    if isfield(s,path)&&~isempty(s.(path)), v=s.(path); return; end
end
end
function scs(v)
numeric(v,1);
assert(ismember(double(v),15*2.^(0:6)),'sixgr:lls6g:config:CSIReportULBWPClock','Report UL-BWP SCS must be an NR numerology.');
end
function numeric(v,minimum)
assert(isnumeric(v)&&~islogical(v)&&isreal(v)&&isscalar(v)&&isfinite(v)&&v>=minimum&&v<=flintmax, ...
    'sixgr:lls6g:config:InvalidCSIReportPeriod','Report calendar values must be finite real numeric scalars in the exact range.');
end
function integer(v,minimum)
numeric(v,minimum);
assert(v==fix(v),'sixgr:lls6g:config:NonIntegralCSIReportPeriod','Report slot coordinates must be exact integers.');
end
function tf=textScalar(v)
tf=(ischar(v)&&isrow(v))||(isstring(v)&&isscalar(v)&&~ismissing(v));
end
function tf=textEqual(v,w)
tf=textScalar(v)&&string(v)==string(w);
end
function tf=has(s,path)
tf=true;
for key=split(string(path),'.').'
    if ~isstruct(s)||~isscalar(s)||~isfield(s,key), tf=false; return; end
    s=s.(key);
end
end
