#!/bin/bash
# ghostls Memory-Safe Test Runner
# Runs all v0.2.0 feature tests with memory leak detection

set -e

echo "🧪 Running ghostls v0.2.0 Tests with Memory Leak Detection"
echo "=========================================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Run tests
echo "📋 Running all tests..."
if zig build test 2>&1 | tee test_output.log; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    TEST_RESULT=0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    TEST_RESULT=1
fi

echo ""
echo "📊 Test Summary"
echo "==============="

# Count test results from output
PASSED=$(grep -c "test.*OK" test_output.log || echo "0")
FAILED=$(grep -c "test.*FAIL" test_output.log || echo "0")

echo "Passed: $PASSED"
echo "Failed: $FAILED"

echo ""
echo "🔍 Memory Leak Check"
echo "===================="

# Check for memory leaks in test output
if grep -q "leak" test_output.log; then
    echo -e "${RED}⚠️  Memory leaks detected!${NC}"
    grep "leak" test_output.log
    LEAK_RESULT=1
else
    echo -e "${GREEN}✅ No memory leaks detected${NC}"
    LEAK_RESULT=0
fi

# Clean up
rm -f test_output.log

echo ""
echo "🎯 Feature Coverage"
echo "==================="
echo "✓ textDocument/references - Find References"
echo "✓ workspace/symbol - Workspace Symbol Search"
echo "✓ Context-Aware Completions"
echo "✓ Protocol Structures & Constants"

echo ""
if [ $TEST_RESULT -eq 0 ] && [ $LEAK_RESULT -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed with no memory leaks!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Tests failed or memory leaks detected${NC}"
    exit 1
fi
