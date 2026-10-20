function ok=testSharedDataStateOnlyTail()
% Production state-only tail ownership, with the same real coded TX,
% CDL/RF samples, exact channel archives and continuous IQ assertions.
% The original test also retains its explicit two-output capture variant.
ok=testSharedDataPhysicalQueue('TDD',false,false);
end
