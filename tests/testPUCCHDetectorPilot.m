function ok=testPUCCHDetectorPilot()
% Infrastructure gate only. Statistical qualification remains separate.
root=tempname(fullfile(pwd,'logs'));
fprintf('DETECTOR_PILOT_ROOT=%s\n',root);
result=runPUCCHDetectorPilot('simulator/configs/validation/pucch_tdd_detector_pilot.yaml',root);
assert(result.PhysicalPilotComplete,'test:DetectorPilotIncomplete', ...
    'Every declared noise/signal case must produce actual acquired-timing RX evidence; inspect %s.',root);
assert(~result.DetectorQualified && all(~result.Summary.DetectorQualified));
ok=true;
end
