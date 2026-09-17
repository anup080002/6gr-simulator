% Read-only verification of the completed capture; no PHY execution or edits.
logRoot='C:/Users/anup0/OneDrive/Documents/Simulator/6GR Simulator_v2_clean_main/logs/research_selected_iq_6be2985f_20260917';
root=fullfile(logRoot,'execution','lls','lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq','committed_source');
iqPath=fullfile(root,'waveform','iq_manifest.csv');
automatic=readtable(iqPath,'TextType','string');
fprintf('AUTOMATIC_IMPORT_COLUMNS %s\n',strjoin(string(automatic.Properties.VariableNames),','));
options=detectImportOptions(iqPath);
disp(options);
% The exporter writes comma-delimited CSV with a first-line header.
iq=readtable(iqPath,'TextType','string','Delimiter',',','ReadVariableNames',true);
fprintf('EXPLICIT_CSV_IMPORT_COLUMNS %s\n',strjoin(string(iq.Properties.VariableNames),','));
assert(height(iq)==8 && all(iq.SampleCount==4915200) && all(iq.ClippedComponents==0));
assert(all(iq.QuantizationMaxError<=.5/32767+eps));
trials=readtable(fullfile(root,'reports','csv','trials.csv'),'TextType','string','Delimiter',',','ReadVariableNames',true);
original=readtable(['C:/Users/anup0/OneDrive/Documents/Simulator/6GR Simulator_v2_clean_main/' ...
    'logs/research_rate082_15aa291c_20260917/execution/lls/research_400mhz_rate082/' ...
    'committed_source/reports/csv/trials.csv'],'TextType','string','Delimiter',',','ReadVariableNames',true);
assert(height(trials)==70 && all(trials.CRCPass & trials.TBExact));
assert(isequal(trials.TBID,original.TBID) && isequal(trials.TBSBits,original.TBSBits));
assert(all(abs(trials.EVMRMS-original.EVMRMS)<1e-10));
fprintf('COMPLETED_CAPTURE_CSV_VERIFICATION_PASS streams=%d trials=%d same_seed_repeat=1 independent_statistical_repeat=0\n',height(iq),height(trials));
