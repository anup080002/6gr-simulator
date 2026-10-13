function ok=testPHYDiagnosticSampleWindow()
% Exact sample-window math only, not physical decoder qualification.
cfg=struct('outputs',struct('phySignalDiagnosticWaveformSamples',256, ...
    'phySignalDiagnosticFFTLength',128));
tx=[zeros(300,1);ones(724,1)];
[t,f,w]=sixgr.link.selectPHYDiagnosticSampleWindow(cfg,tx,1024);
assert(isequal(t,(301:556).') && isequal(f,(301:428).') && w.TXNonzeroSampleObserved);
assert(w.WaveformWindowStartSample==301 && w.SpectrumWindowStartSample==301);
[t,f,w]=sixgr.link.selectPHYDiagnosticSampleWindow(cfg,tx,400);
assert(isequal(t,(145:400).') && isequal(f,(273:400).'));
assert(w.WaveformWindowSamples==256 && w.SpectrumWindowSamples==128);
[t,~,w]=sixgr.link.selectPHYDiagnosticSampleWindow(cfg,[zeros(512,1),ones(512,1)],512);
assert(isequal(t,(1:256).') && ~w.TXNonzeroSampleObserved, ...
    'Silent declared port must not be replaced by another active port.');
[t,f,~]=sixgr.link.selectPHYDiagnosticSampleWindow(cfg,ones(20,1),20);
assert(isempty(t) && isempty(f));
cfg.outputs.phySignalDiagnosticFFTLength=4096;
[t,f,~]=sixgr.link.selectPHYDiagnosticSampleWindow(cfg,tx,1024);
assert(isequal(t,(301:556).') && isequal(f,(1:1024).'), ...
    'Different display/FFT lengths must fit on the same original clock.');
fprintf('PHY_DIAGNOSTIC_WINDOW_PASS bounded original-clock sample selection; no receiver timing change.\n');
ok=true;
end
