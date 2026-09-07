function timing=resolveULTimingAdvanceOffset(common,frequencyRange)
% TS 38.133 V18.8.0 Table 7.1.2-2 and TS 38.213 clause 4.2.
% Resolve the UE's received common-cell IE, not a transmitter config value.
% Both FR1 FDD and TDD default to 25600 Tc when the IE is absent. A received
% n39936 is also permitted for FDD (table note 1); do not infer it from duplex.
if ~isstruct(common) || ~isscalar(common) || ...
        ~isfield(common,'Source') || string(common.Source)~="decoded_sib1" || ...
        ~isfield(common,'TimingAdvanceOffsetPresent') || ...
        ~islogical(common.TimingAdvanceOffsetPresent) || ~isscalar(common.TimingAdvanceOffsetPresent) || ...
        ~isfield(common,'TimingAdvanceOffset')
    error('sixgr:phy:frame:MissingReceivedULTimingAuthority', ...
        'Require a received common-cell configuration with explicit IE presence.');
end
range=sixgr.phy.frame.FrequencyRangeResolver.resolve('FrequencyRange',frequencyRange);
present=common.TimingAdvanceOffsetPresent;
value=string(common.TimingAdvanceOffset);
if ~isscalar(value) || ismissing(value) || (~present && strlength(value)~=0)
    error('sixgr:phy:frame:InconsistentTimingOffsetPresence', ...
        'Absent n-TimingAdvanceOffset must remain absent, not retain an old value.');
end
if string(range.FrequencyRange)=="FR1"
    ticks=25600;
    source="TS_38_133_V18_8_0_table_7_1_2_2_FR1_absent_IE_default";
    if present
        enums=["n0","n25600","n39936"]; values=[0 25600 39936];
        index=find(enums==value,1);
        if isempty(index)
            error('sixgr:phy:frame:InvalidReceivedTimingOffset','Invalid received n-TimingAdvanceOffset enum.');
        end
        ticks=values(index); source="received_SIB1_n_TimingAdvanceOffset";
    end
else
    % The pinned table has fixed FR2 timing; do not apply an FR1 enum to it.
    if present
        error('sixgr:phy:frame:UnsupportedFR2TimingOffsetIE', ...
            'The pinned FR2 timing profile requires the table value, not an FR1 offset enum.');
    end
    ticks=13792; source="TS_38_133_V18_8_0_table_7_1_2_2_FR2";
end
timing=struct('NTAOffset_Tc',int64(ticks), ...
    'Seconds',double(ticks)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond), ...
    'FrequencyRange',string(range.FrequencyRange),'IEPresent',present, ...
    'ReceivedIE',value,'Source',source, ...
    'Reference','3GPP_TS_38.133_V18.8.0_Table_7.1.2-2', ...
    'WaveformTimingApplied',false);
end
