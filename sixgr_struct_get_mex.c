#include "mex.h"
#include <string.h>

static mxArray* duplicate_or_empty(const mxArray* in) {
    if (in == NULL) {
        return mxCreateDoubleMatrix(0, 0, mxREAL);
    }
    return mxDuplicateArray(in);
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    const mxArray* cur = NULL;
    const mxArray* defVal = NULL;
    char* path = NULL;
    size_t pathLen = 0;
    char* segStart = NULL;
    char* dot = NULL;
    mxArray* out = NULL;

    if (nrhs < 2 || nrhs > 3) {
        mexErrMsgIdAndTxt("sixgr:struct_get_mex:BadNrhs", "Expected 2 or 3 inputs.");
    }

    if (!mxIsStruct(prhs[0]) || mxGetNumberOfElements(prhs[0]) != 1) {
        if (nrhs >= 3) {
            plhs[0] = duplicate_or_empty(prhs[2]);
        } else {
            plhs[0] = mxCreateDoubleMatrix(0, 0, mxREAL);
        }
        return;
    }

    if (!mxIsChar(prhs[1])) {
        if (nrhs >= 3) {
            plhs[0] = duplicate_or_empty(prhs[2]);
        } else {
            plhs[0] = mxCreateDoubleMatrix(0, 0, mxREAL);
        }
        return;
    }

    if (nrhs >= 3) {
        defVal = prhs[2];
    }

    pathLen = mxGetNumberOfElements(prhs[1]);
    if (pathLen == 0) {
        plhs[0] = duplicate_or_empty(defVal);
        return;
    }

    path = mxArrayToString(prhs[1]);
    if (path == NULL) {
        plhs[0] = duplicate_or_empty(defVal);
        return;
    }

    cur = prhs[0];
    segStart = path;

    while (segStart != NULL && *segStart != '\0') {
        char saved = '\0';
        const mxArray* next = NULL;

        dot = strchr(segStart, '.');
        if (dot != NULL) {
            saved = *dot;
            *dot = '\0';
        }

        if (!mxIsStruct(cur) || mxGetNumberOfElements(cur) != 1) {
            mxFree(path);
            plhs[0] = duplicate_or_empty(defVal);
            return;
        }

        next = mxGetField(cur, 0, segStart);
        if (next == NULL) {
            mxFree(path);
            plhs[0] = duplicate_or_empty(defVal);
            return;
        }
        cur = next;

        if (dot != NULL) {
            *dot = saved;
            segStart = dot + 1;
        } else {
            segStart = NULL;
        }
    }

    out = mxDuplicateArray(cur);
    mxFree(path);
    plhs[0] = out;
    (void)nlhs;
}

