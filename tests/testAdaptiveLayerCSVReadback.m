function ok=testAdaptiveLayerCSVReadback(retainedSource)
% Serialization fixtures (not PHY results), plus optional retained evidence.
% Rank-one scalar-looking strings must remain vectors when later rows adapt.
setup6GRSimToolkit('Verbose',false);
sixgr.db.deactivateArtifactStore();
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
fields=["PostEqSINRPerLayer_dB","ResidualInterLayerPowerPerLayer","EVMPerLayer_rms", ...
    "BeamScoreVector_dB","TopBeamIndexSet","TopBeamGainSet_dB"];
T=table((1:5)',ones(5,1),[1;1;1;1;2], ...
    ["1";"2";"3";"4";"-5.28878|-5.54566"], ...
    ["0";"0";"0";"0";"0.219837|0.190546"], ...
    ["0.1";"0.2";"0.3";"0.4";"1.9219353184964225|1.9589892910284126"], ...
    repmat(string(repmat('a',1,300000)),5,1), ...
    'VariableNames',{'Slot','UEIndex','Layers','PostEqSINRPerLayer_dB', ...
    'ResidualInterLayerPowerPerLayer','EVMPerLayer_rms','LongReceivedEvidence'});
T.BeamScoreVector_dB=["NaN";"NaN";"1.2|2.3|3.4";"NaN";"2.1|1.2|0.3"];
T.TopBeamIndexSet=["NaN";"NaN";"3|2";"NaN";"1|2"];
T.TopBeamGainSet_dB=["NaN";"NaN";"3.4|2.3";"NaN";"2.1|1.2"];
path=fullfile(root,'air_interface','csv','ul_pusch_trials.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
localCheck(root,path,T,fields);
if nargin>0
    before=sixgr.phy.waveform.WaveformHash.file(retainedSource);
    % Independent inspection with explicitly declared text, no inference.
    options=detectImportOptions(retainedSource,'Delimiter',',','VariableNamingRule','preserve');
    options.VariableNamesLine=1; options.DataLines=[2 Inf];
    options=setvartype(options,cellstr(fields),'string');
    expected=readtable(retainedSource,options);
    assert(any(contains(expected.PostEqSINRPerLayer_dB,'|')), ...
        'The retained case must include genuine multilayer measurements.');
    copyfile(retainedSource,path);
    localCheck(root,path,expected,fields);
    assert(sixgr.phy.waveform.WaveformHash.file(retainedSource)==before);
    fprintf('ADAPTIVE_LAYER_RETAINED_CSV_PASS rows=%d source_unchanged=1\n',height(expected));
end
fprintf('ADAPTIVE_LAYER_CSV_READBACK_PASS canonical_and_analytics_and_persisted_KPI=1\n');
ok=true;
end

function localCheck(root,path,expected,fields)
canonical=sixgr.util.csvReadTable(path,'TextType','string');
analytics=sixgr.analytics.loadAllTrialData(root);
raw=sixgr.kpi.loadDirectionRawTables(struct(),'RunFolder',root,'PreferPersistedPrimary',true);
for name=fields
    for item={canonical,analytics.ul,raw.UL}
        got=item{1};
        assert(height(got)==height(expected) && isstring(got.(name)) && ...
            isequaln(got.(name),string(expected.(name))), ...
            'test:AdaptiveLayerCSVValueLost', ...
            '%s lost scalar/vector values during canonical, analytics or KPI readback.',name);
    end
end
% Repeated finalization must preserve, not turn the later vector into NaN.
sixgr.util.csvWriteTable(path,canonical,'PreserveSchema',true);
again=sixgr.util.csvReadTable(path,'TextType','string');
for name=fields, assert(isequaln(again.(name),string(expected.(name)))); end
end
