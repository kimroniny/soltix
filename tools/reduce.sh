#!/bin/sh


# This script reduces a buggy (POSSIBLE BUG: MUTATION MEMORY ERROR) pair of original and
# mutated contract files (generated by isolate.sh) by attempting to remove all function
# bodies that have no apparent effect on the test case (i.e. the bug is still present
# afterwards).
#
# Results are stored in <INPUT_DIR>-reduced-<num>
# where <num> represents the current reduction iteration

if test "$#" != 2; then
	echo "Usage: ./reduce.sh [isolate.sh'ed-directory] [failed-mutation-number]"
	exit 1
fi

INPUT=`realpath "$1"` # realpath drops trailing /
# TODO also allow for instrumented instead of mutated contract
       ORIGINAL_FILE="$INPUT/original.sol"
FAILED_MUTATION_FILE="$INPUT/mutated${2}.sol"
OUTPUT="${INPUT}-reduced"

if test -d "$OUTPUT"-1; then
	echo Output directory "$OUTPUT"-1 already exists.
	echo Delete all output dirs with rm -rf $OUTPUT-'*' first
	exit 1
fi

if ! test -f "$ORIGINAL_FILE" || ! test -f "$FAILED_MUTATION_FILE"; then
	echo Input directory is missing $ORIGINAL_FILE or $FAILED_MUTATION_FILE 
	echo "mutated.sol must be created manually from the mutated<num>sol that failed"
	exit 1
fi

FUNCTION_LIST_FILE=$PWD/_functionList.tmp
if ! ./run-soltix.sh "$ORIGINAL_FILE" --generateContractFunctionsFile="$FUNCTION_LIST_FILE" >_mutator-log.tmp 2>&1; then
	echo run-soltix.sh failed - see _mutator-log.tmp
	exit 1
fi

TOTAL_FUNCTIONS=`wc -l $FUNCTION_LIST_FILE | awk '{print $1}'`

echo NOTE:
echo "1. Runtime tautology correctness should be enabled in the mutator (Configuration.checkRuntimeTautologyCorrectness = true)"
echo    to ensure that reductions do not break tautologies
echo 2. The case contains $TOTAL_FUNCTIONS functions, requiring a corresponding number of reductions
echo

while test "$USER_INPUT" != y && test "$USER_INPUT" != n; do
	printf "Proceed? [y/n] "
	read USER_INPUT
	if test "$USER_INPUT" = n; then
		exit 1
	fi
done

prepare_directory() {
	if ! cp -R "$INPUT" $1; then
		echo Error
		exit 1
	fi

	# Delete all mutations, create mutated0.sol below
	rm "$1"/mutated*.sol
}

ERROR_STRING="Memory state difference between"

# Strategy: For each function in every contract, we try to remove it from both the original
# and mutated test case, and check whether storage log differences remain. If this is the
# case, we assume that the function can be emptied without hiding the bug we're currently
# analyzing, and so the function is kept in all future removal operations
GOOD_REDUCTIONS=""
i=1
for candidate in `cat "$FUNCTION_LIST_FILE"`; do
	CUR_DIR="${OUTPUT}-${i}"
	prepare_directory $CUR_DIR
	if test "$GOOD_REDUCTIONS" = ""; then
		CURRENT_REDUCTIONS="$candidate"
	else
		CURRENT_REDUCTIONS="${GOOD_REDUCTIONS},${candidate}"
	fi

	printf "Trying $i of $TOTAL_FUNCTIONS : $candidate in $CUR_DIR ... "
	i=`expr $i + 1`

	echo "$CURRENT_REDUCTIONS" >"$CUR_DIR"/reductions.txt

	if ! ./run-soltix.sh "$ORIGINAL_FILE"        "--reduceFunctions=$CURRENT_REDUCTIONS" "--solidityOutput=$CUR_DIR/original.sol" >/dev/null 2>&1; then
		echo "MUTATOR FAILED (original)"	
		continue
	fi

	if ! ./run-soltix.sh "$FAILED_MUTATION_FILE" "--reduceFunctions=$CURRENT_REDUCTIONS" "--solidityOutput=$CUR_DIR/mutated0.sol" >/dev/null 2>&1; then
		echo "MUTATOR FAILED (mutation)"
		continue
	fi

	./run-one-test.sh "$CUR_DIR" 1 >_test-out.tmp 2>&1
	# We assume that tautology correctness checking is enabled. By checking for the absence
	# of tautology error events, we can ensure that the removal of a function body - e.g. f1 in
	#     uint x = 123;
	#     function f1() { x = 456; }
	#     function f2() { tautology(... x ...); }
	# does not cause mutated code to change state incorrectly. It is tempting to re-instrument
	# and re-mutate instead, but the removals will probably change PRNG values to the extent
	# that any thusly generated new code probably doesn't exhibit the problem we're analyzing
	# anymore.
	#
	# With the tautology check in place, we can rule out the main known source of reduction-
	# induced  problems and don't care whether the storage log differences changed - only the 
	# pressence of differences matters
	if grep "$ERROR_STRING" _test-out.tmp >/dev/null && ! grep TAUTOLOGY_ERROR "$PATH_MAIN_RESULTS_DIR"/mutated0-profiling-log.log >/dev/null; then
		echo OK
		# Keep this reduction
		GOOD_REDUCTIONS="$CURRENT_REDUCTIONS"
	else
		echo BAD REDUCTION
	fi
done

