function ok = testLogicalAnyReduction()
%TESTLOGICALANYREDUCTION Vector runtime flags must reduce deterministically.

assert(~sixgr.util.logicalAny([]));
assert(~sixgr.util.logicalAny([false false]));
assert(sixgr.util.logicalAny([false true false]));
assert(~sixgr.util.logicalAny([0 NaN 0]));
assert(sixgr.util.logicalAny([0 NaN 2]));
assert(sixgr.util.logicalAny(["false" "retx"]));
assert(~sixgr.util.logicalAny(["false" "off" "missing"]));
ok = true;
end
