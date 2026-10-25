function value=resolveULTimingAdvanceOffsetValue(present,ie,frequencyRange)
% Pure common-offset arithmetic shared by cell configuration and UE decode.
% TS 38.133 V18.8.0 Table 7.1.2-2. This does NOT establish that an IE was
% transmitted, received, installed, or applied to a physical waveform.
assert(islogical(present) && isscalar(present), ...
    'sixgr:phy:frame:InconsistentTimingOffsetPresence','Declare original IE presence as a logical scalar.');
assert((ischar(ie) && (isrow(ie)||isempty(ie))) || ...
    (isstring(ie) && isscalar(ie) && ~ismissing(ie)), ...
    'sixgr:phy:frame:InconsistentTimingOffsetPresence','Timing offset IE must be original scalar text.');
ie=string(ie);
assert(present || strlength(ie)==0,'sixgr:phy:frame:InconsistentTimingOffsetPresence', ...
    'Absent n-TimingAdvanceOffset must not retain a stale IE value.');
range=sixgr.phy.frame.FrequencyRangeResolver.resolve('FrequencyRange',frequencyRange);
rule="TS_38_133_V18_8_0_table_7_1_2_2_FR1_absent_IE_default";
if string(range.FrequencyRange)=="FR1"
    ticks=25600;
    if present
        enums=["n0","n25600","n39936"]; values=[0 25600 39936];
        index=find(enums==ie,1);
        assert(~isempty(index),'sixgr:phy:frame:InvalidReceivedTimingOffset', ...
            'Invalid n-TimingAdvanceOffset enum.');
        ticks=values(index); rule="explicit_common_n_TimingAdvanceOffset";
    end
else
    assert(~present,'sixgr:phy:frame:UnsupportedFR2TimingOffsetIE', ...
        'The pinned FR2 profile uses the table value, not an FR1 offset enum.');
    ticks=13792; rule="TS_38_133_V18_8_0_table_7_1_2_2_FR2";
end
value=struct('NTAOffset_Tc',int64(ticks),'FrequencyRange',string(range.FrequencyRange), ...
    'IEPresent',present,'IEValue',ie,'Rule',rule, ...
    'Reference',"3GPP_TS_38.133_V18.8.0_Table_7.1.2-2");
end
