function tf = shouldPreserveCompletedRunOnPostRunFailure(~)
%SHOULDPRESERVECOMPLETEDRUNONPOSTRUNFAILURE Always fail closed.
%
% Execution success and finalization/publication success are independent.
% Any exception after waveform execution is still a terminal finalization
% failure and must remain visible in the root verdict. Returning true here
% previously allowed a real publication exception to leave a falsely green
% run. The function remains only as a compatibility seam for callers.
tf = false;
end
