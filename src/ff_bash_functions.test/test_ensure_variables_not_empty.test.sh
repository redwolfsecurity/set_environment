#!/usr/bin/env bash

################################################################################
# UNIT TEST: ensure_variables_not_empty
#
# This function validates ensure_variables_not_empty across various cases.
# It logs results for each test case and summarizes outcomes.
################################################################################
function test_ensure_variables_not_empty {

    echo "Running unit test: test_ensure_variables_not_empty"

    # Mock error function to capture error logs
    local ERROR_LOG=""
    function error {
        local CALLER="$1"
        shift
        ERROR_LOG+="[${CALLER}] $*\n"
    }
    export -f error

    # Prepare test environment
    export VAR_NONEMPTY="value"
    export VAR_EMPTY=""
    unset VAR_UNDEFINED

    local VAR_LIST
    local SUCCESS_COUNT=0
    local FAILURE_COUNT=0

    # === CASE 1: All non-empty (array style) ===
    VAR_LIST=(VAR_NONEMPTY)
    ERROR_LOG=""
    ensure_variables_not_empty "TEST_CASE_1" "${VAR_LIST[@]}"
    if [[ $? -eq 0 ]]; then
        echo "✅ CASE 1: All non-empty (array style) ... passed"
        ((SUCCESS_COUNT++))
    else
        echo "❌ CASE 1: All non-empty (array style) ... failed"
        echo -e "$ERROR_LOG"
        ((FAILURE_COUNT++))
    fi

    # === CASE 2: Contains empty variable ===
    VAR_LIST=(VAR_NONEMPTY VAR_EMPTY)
    ERROR_LOG=""
    ensure_variables_not_empty "TEST_CASE_2" "${VAR_LIST[@]}"
    if [[ $? -eq 0 ]]; then
        echo "❌ CASE 2: Contains empty variable ... failed (expected error)"
        ((FAILURE_COUNT++))
    else
        echo "✅ CASE 2: Contains empty variable ... passed"
        echo -e "$ERROR_LOG"
        ((SUCCESS_COUNT++))
    fi

    # === CASE 3: Contains undefined variable (string style) ===
    ERROR_LOG=""
    ensure_variables_not_empty "TEST_CASE_3" VAR_NONEMPTY VAR_UNDEFINED
    if [[ $? -eq 0 ]]; then
        echo "❌ CASE 3: Contains undefined variable (string style) ... failed (expected error)"
        ((FAILURE_COUNT++))
    else
        echo "✅ CASE 3: Contains undefined variable (string style) ... passed"
        echo -e "$ERROR_LOG"
        ((SUCCESS_COUNT++))
    fi

    # === CASE 4: All invalid (empty + undefined) ===
    ERROR_LOG=""
    ensure_variables_not_empty "TEST_CASE_4" VAR_EMPTY VAR_UNDEFINED
    if [[ $? -eq 0 ]]; then
        echo "❌ CASE 4: All invalid (empty + undefined) ... failed (expected error)"
        ((FAILURE_COUNT++))
    else
        echo "✅ CASE 4: All invalid (empty + undefined) ... passed"
        echo -e "$ERROR_LOG"
        ((SUCCESS_COUNT++))
    fi

    # === CASE 5: Invalid usage - no variables provided ===
    ERROR_LOG=""
    ensure_variables_not_empty "TEST_CASE_5"
    if [[ $? -eq 0 ]]; then
        echo "❌ CASE 5: Invalid usage - no variables provided ... failed (expected error)"
        ((FAILURE_COUNT++))
    else
        echo "✅ CASE 5: Invalid usage - no variables provided ... passed"
        echo -e "$ERROR_LOG"
        ((SUCCESS_COUNT++))
    fi

    # === CASE 6: Missing caller function name ===
    ERROR_LOG=""
    ensure_variables_not_empty "" VAR_NONEMPTY
    if [[ $? -eq 0 ]]; then
        echo "❌ CASE 6: Missing caller function name ... failed (expected error)"
        ((FAILURE_COUNT++))
    else
        echo "✅ CASE 6: Missing caller function name ... passed"
        echo -e "$ERROR_LOG"
        ((SUCCESS_COUNT++))
    fi

    # === FINAL SUMMARY ===
    local TOTAL_CASES=$((SUCCESS_COUNT + FAILURE_COUNT))
    local SUCCESS_LABEL="test"
    local FAILURE_LABEL="test"
    [[ "${SUCCESS_COUNT}" -ne 1 ]] && SUCCESS_LABEL="tests"
    [[ "${FAILURE_COUNT}" -ne 1 ]] && FAILURE_LABEL="tests"

    if [[ "${FAILURE_COUNT}" -eq 0 ]]; then
        echo "✅ All ${SUCCESS_COUNT} ${SUCCESS_LABEL} in test_ensure_variables_not_empty passed!"
        return 0
    else
        echo ""
        echo "❌ ${FAILURE_COUNT} ${FAILURE_LABEL} in test_ensure_variables_not_empty failed!"
        echo "Note: ${SUCCESS_COUNT} ${SUCCESS_LABEL} passed."
        return 1
    fi
}
export -f test_ensure_variables_not_empty

test_ensure_variables_not_empty
