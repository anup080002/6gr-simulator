function ok = testHARQIRCombiningGain()
%TESTHARQIRCOMBININGGAIN Reuse the HARQ exercise to guard real combining rows.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
ok = testLLSHARQExercise();
end
