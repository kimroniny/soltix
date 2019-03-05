#!/bin/sh

if test "$#" -lt 1; then
	echo Usage: "./run-test.sh [solidity-file.sol] [soltix-args...]"
	exit 1
fi
INPUT=$1
shift

if test "$SOLC_BINARY_PATH" = ""; then
	echo Error: SOLC_BINARY_PATH not set.
	echo The caller of this script could source settings.cfg.sh in test-env for this, generated by setup.sh
	exit 1
fi

# solc invocation:
# timestamp to minimize (but not avoid 100%) race conditions for now
AST_FILE_PATH=/tmp/solc.ast-`date '+%s'`
AST_ERR_PATH=/tmp/solc.err-`date '+%s'`
if ! "$SOLC_BINARY_PATH" --ast-json $INPUT >$AST_FILE_PATH 2>$AST_ERR_PATH; then
	cat $AST_ERR_PATH 
	rm -f "$AST_FILE_PATH" "$AST_ERR_PATH"
	echo Error: solc failed, see output above
	exit 1
else
	cat $AST_FILE_PATH | normalize-ast-json.sh | strip-ast-json-junk.sh  | run.sh "$@"
	STATUS=$?
	rm -f "$AST_FILE_PATH" "$AST_ERR_PATH"
	exit $STATUS 
fi

