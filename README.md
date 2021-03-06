<img src="/img/soltix.png" width="196">


# SOLTIX: Scalable automated framework for testing Solidity compilers.

SOLTIX is a framework for automated testing of Solidity compilers supported by the [Ethereum Foundation](https://www.ethereum.org/) and the [ICE Center](http://www.ice.ethz.ch/blockchain), [ETH Zurich](https://www.ethz.ch/en.html). 
The research and development of SOLTIX started at the ICE center, as the MSc thesis project of [Nils Weller](mailto:nweller@student.ethz.ch) under the supervision of [Dr. Petar Tsankov](https://twitter.com/ptsankov) and [Prof. Martin Vechev](martin.vechev@inf.ethz.ch).

The project now is an open platform welcoming contributors from the Ethereum community. To learn more about the framework, build on top of it or extend it to other virtual machines, please get in touch with the core team and contributors at our [Discord group](https://discord.gg/XKSVavS).


# Bugs found so far

So far SOLTIX has found several bugs in the official [Solidity compiler](https://solidity.readthedocs.io/en/v0.4.24/installing-solidity.html) (`solc`) and [ganache-cli](https://github.com/trufflesuite/ganache-cli).

## 1. Solidity compiler bugs

SOLTIX has found the following two bugs in the `solc` solidity compiler:

   1. [Exponentiation bug](https://github.com/ethereum/solidity/issues/4893): This bug results in incorrect computations of exponents. The bug was fixed in [version 0.4.25](https://github.com/ethereum/solidity/releases/tag/v0.4.25).

   2. [Internal compiler error bug](https://github.com/ethereum/solidity/issues/5130): This bug results in an internal compiler error in various solc versions. The bug was fixed in version 0.5.1.

## 2. Ganache-cli bugs

SOLTIX has also discovered two in `ganache-cli`:

   1. [Shift and exponentiation crashes](https://github.com/trufflesuite/ganache-cli/issues/575): The bugs have not been fixed yet.


# SOLTIX overview

SOLTIX tests the Solidity compiler and, in turn, the Ethereum Virtual Machine (EVM) in a fully automated way. 
For this purpose, SOLTIX provides the following two testing modules:

## 1. Testing via synthesis of random Solidity contracts
 
The synthesis module tests the Solidity compiler without requiring access to Solidity contracts or transactions. 
The high-level flow is illustrated in the following figure:
<img src="/img/synthesis-testing.png">

To test the compiler, SOLTIX is provided with a set of parameters (such as number of variables, functions, etc.) which 
define the Solidity contract which will be synthesized. As a first step, SOLTIX generates transactions and a Solidity contract.
The synthesized Solidity contract is instrumented by `emit` statements that raise an error in case the contract execution
is unexpected. In the illustrated example, SOLTIX will execute the transaction `foo(10)` which should follow the `false`
branch of the `if (x != 5)` condition. Therefore, SOLTIX throws an error in case the contract's execution proceeds along the
`true` branch. To test the compiler, SOLTIX compiles the Solidity contract into EVM bytecode and executes it, keeping track
of all emitted events. Based on the the emitted events, SOLTIX reports an error if an error event has been emitted.

 
## 2. Testing via synthesis of semantically equivalent Solidity smart contracts

The equivalence testing module works by generating a large number of semantically equivalent Solidity contracts for a given
set of transactions and tests whether they all reach the same state when the transactions are executed. The high-level flow
of this module is illustrated in the following figure:

<img src="/img/equivalence-testing.png">

The input to this module is a Solidity contract and a sequence of transactions (e.g. `foo(10)`, `foo(15)`). First, SOLTIX 
executes the Solidity contract with the provided transactions and records relevant execution profile information, such as
the possible variable values observed at different program counters. In our example, the variable `x` is assigned values
`11` and `16` at Line 4 of the contract (for the provided two transactions). Next, SOLTIX generates a large number of
semantically equivalent Solidity contracts. In our example, it introduces a new `if (x/2 > y)` statement which always holds
for the provided transactions. The synthesized Solidity contracts are compiled using `solc` and executed, while recording the
final state of the contracts. The final states are compared to assess whether the compilation step was successful or not.

The remaining part of this document how knowledge on expected behavior is obtained, what types of contracts are
generated and how, and how the original equivalence testing technique is integrated to mutated programs. 

# Contents
1. Getting started
    * Requirements 
    * Build
    * Use
        * Generation
        * Execution
2. Known limitations
3. Technical details
    * Contract behavior
    * Code generation 
    * Equivalence-testing transformation


# Getting started

## Requirements

* Operating system: Linux
* Java 8+
* Maven
* NodeJS 10+ (to use truffle and ganache-cli)
* GNU C++ (g++)

For Ubuntu Linux, the dependencies can be installed with apt-get using the
commands listed below.


g++:

        sudo apt-get install build-essential

Java 8+:

        sudo apt-add-repository ppa:webupd8team/java
        sudo apt-get update
        sudo apt-get install oracle-java8-installer
        sudo apt-get install oracle-java8-set-default

Maven:

        sudo apt-get install maven

NodeJS:

        sudo apt-get install nodejs

If nodejs is already installed in a version older than 10, it can be updated 
using the following commands:

        sudo npm cache clean -f
        sudo npm install -g n
        sudo n stable 

Instead of installing or updating nodejs for the whole system, it is also
possible to download and build a recent nodejs version in the user's home
directory by executing the script:

        ./tools/node-local-setup.sh

This requires no sudo access and creates nodejs binaries in the ~/local/bin
directory. 

## Build

To build and configure the ECTF software, execute the interactive setup 
script and answer its questions:

        ./setup.sh

This will generate a settings.cfg.sh file that contains various configurable
settings, such as the compiler to be used (solcjs or solc) and its 
optimization settings.

## Use

A basic introduction to the most important framework commands is given below.
A technical overview on what these commands do is described at the end of this
document in the [technical details](#technical-details) section.

### Introduction

As described in the [overview](#framework-overview), the framework can execute
smart contracts - using randomly generated transactions - and analyze their
behavior to infer potential miscompilations. 

The test process for one smart contract can be separated into

1. An optional contract generation phase
2. A contract execution phase

The framework's contract generation functions can be used to produce the initial 
_seed_ program for the execution phase, but an externally supplied contract may 
be used instead as well.

If equivalence-testing transformation is requested, the contract execution phase will
involve multiple intertwined additional steps to profile the supplied seed
program, generate multiple variants of the seed program, and execute them to
detect behavioral differences.

As described in the [contract behavior](#contract-behavior) section, executing
contracts without any equivalence-testing transformations can also be produce meaningful
information on program execution correctness, particularly for contracts that
are self-contained due to internal correctness checks - as described below - or to compare
the behavior of the same contract executed at varying optimization levels.


### Generation

This section describes the optional seed program generation phase in the test
process introduced above. There are two types of contracts that can be generated. 
Both of them contain storage variables, as well as functions that differ in the
code they contain: 

1. _Assignment sequence_ (AS) contracts use a sequence of assignment expression statements
2. _Complete_ contracts use random statement combinations including (potentially nested) control structures

AS contracts contain built-in correctness checks that verify the correct program
behavior - at the cost of structural simplicity. Complete contracts add more complexity,
but have no such built-in correctness checks. This makes their combination with
equivalence-testing or different optimization level testing particularly desirable to obtain
meaningful tests.

#### Generating a single contract

A random contract with a Solidity file and test transactions can be generated
using the _generate-contract.sh_ script.

A contract is generally identified by the following 6-tuple:

1. Random number seed number
2. Number of functions in contract
3. Minimum number of code units per function
4. Maximum number of code units per function
5. Number of variables in contract
6. Choice of contract type (--assignmentSequence or --complete)

Since random numbers are currently generated by the Java PRNG, the same 6-tuple
may however produce programs that vary between systems using different Java PRNG 
versions.


*Example*

To generate an AS contract with a PRNG seed of 0, 10 functions, 1-2 code units
per function, and 20 variables in the directory "X", run:

        ./soltix/bin/generate-contract.sh 0 10 1 2 20 X --assignmentSequence 

This will automatically also generate 4 semantically equivalent contract files, since the
expected behavior of AS is known at generation time.

To do the same thing for a contract of type "complete":

        ./soltix/bin/generate-contract.sh 0 10 1 2 20 X --complete

This will not generate any mutations, since complete contracts must first be
executed with instrumentation to measure their behavior.


#### Generating a contract set

A contract _set_ containing multiple contracts can be generated using the
_generate-contract-set.sh_ script. Its first argument is the count of contracts to
generate, the remaining arguments are the same as in the single-contract case above - 
with the given seed getting incremented for each generated contract.

To generate 5 contracts in sub-directories to directory "X" with the same properties
as in the precding example (10 functions, 1-2 code units per function, 20 variables)
from seed 0 to 4, run:

        ./soltix/bin/generate-contract-set.sh 5 0 10 1 2 20 X --complete

### Execution

This section describes the execution phase in the test process summarized in the
[introduction](#introduction). It works on contracts that were either generated in 
the generation phase described above, or made available from some external source. 
The execution phase may involve multiple execution and code generation steps if
semantically equivalent transformations are requested.

Generated contracts are already available in the form of a truffle-compatible
project directory containing the contract, a deployment script, and a test file 
with the transactions. Externally supplied contracts are expected to be plain .sol
files, but will be stored in a truffle-compatible intermediate project directory 
as part of the execution prepartions - with randomly generated deployment and 
transaction files. As described in the [test process](#test-process) section,
these can be edited for debugging purposes.

The framework produces three major messages to summarize the exeuction results:

1. OK - No errors were detected (whether this indicator is meaningful depends on
the test constellation, as described in the [generation introduction](#generation)) 
2. POSSIBLE BUG: EXPR\_ERROR - An internal AS contract check detected an unexpected
execution result 
3. POSSIBLE BUG: EVENT LOG ERROR - The event logs between two contracts that
should be semantically equivalent differ (as described in the section on
[contract behavior](#contract-behavior), this probably means that they
ended up with different final storage variable values

Additional result messages may highlight other problems detected during the 
generation or execution, but do not usually indicate compiler or execution errors.
For example, if a "FRAMEWORK ERROR", "CLIENT ERROR" or "STACK TOO DEEP ERROR"
occurs, it typically indicates a limitation in some component rather than a bug.

*IMPORTANT:* Generated contracts are designed to be well-behaved for their input, but 
externally supplied contracts tend to produce many runtime errors, such as
"INVALID OPCODE" (since the randomly generated transactions cannot avoid invalid
operations - such as negative shift operands or divison by zero - for arbitrary input
contracts). These cases can generally be distinguished from possible bug cases
listed above and should usually be ignored. For generated contracts, "INVALID OPCODE"
errors and generic "ERROR" errors (EVM crashes) can also indicate compilation or
execution problems. Errors are evaluated, and error messages are generated, in the
test-env-truffle/bin/run-one-test.sh script.

As discussed in the [known limitations](#known-limitations) section, it is easy
to run into generation or execution limitations for large contracts (designated by
errors such as "FRAMEWORK ERROR" or "CLIENT ERROR"). These result in various types 
of framework errors that must either be ignored or get addressed by reducing the 
contract size.

#### Executing a single contract

A single generated test contract can be executed using the _run-one-test.sh_ script,
optionally with a specified number of semantically equivalent mutations to execute as well. For a
given generated contract directory X, it can be executed with no (zero) mutations:

        ./test-env-truffle/bin/run-one-test.sh X 0

or, with more verbose output to debug technical issues in the test environment:  
        
        ./test-env-truffle/bin/do-run-one-test.sh X 0

If the contract in X is an AS program, this will produce an error for internally
detected unexpected results. For a complete program, the test does not expose unexpected
computational results, since no expected behavior to compare the execution with is 
known. However, a runtime exception would still indicate a miscompilation or execution 
environment bug.

Externally supplied contracts can be executed as well by supplying the Solidity file
instead of a directory, e.g. for a code file x.sol:

        ./test-env-truffle/bin/run-one-test.sh x.sol 2

This generates random transactions on the fly.

##### Input and results 

Input and output data for one such execution is stored in the temporary directory:

        ./test-env-truffle/_current-project

The most recent log of "emit" statement events produced by the contract is actually 
stored in the input directory:

        ./test-env-truffle/_current-project/input/profiling-events.log

For multiple executions (original, instrumented and mutated), the event logs are
stored in:

        ./test-env-truffle/_current-project/output/main_results/*-profiling-log.log

##### Semantically equivalent transformations 

To run the test with e.g. 2 semantically equivalent mutations instead of none:

        ./test-env-truffle/bin/run-one-test.sh X 2

This will also report divergences between the behavior of the original contract and
its mutations as a problem. For AS contracts, 4 mutated programs are already created
during generation time, as described above (which limits the maximum number of possible 
mutations to 4 as well). For complete contracts, an additional instrumentation step 
is executed to obtain variable environment state and create mutated programs.


##### Different Optimization Testing 

Instead of specifying a mutations count, it is also possible to pass the argument
"optimize" in order to compare the results for a single contract once compiled with
and once without optimization enabled:

        ./test-env-truffle/bin/run-one-test.sh x.sol optimize

#### Executing a set of contracts

A whole set of contracts can be executed using the _run-all-tests.sh_ script. If the
contract set directory was generated using the _generate-contract-set.sh_ script, it
is automatically in the correct form. 

Externally supplied contracts are expected to follow the convention of having one
sub-directory containing one contract file each, e.g. for a directory X:

        X/c1/contract.sol
        X/c2/contract.sol
        X/c3/contract.sol

A generated or externally supplied contract set directory X can be executed with 1
semantically equivalent transformation using:

        ./test-env-truffle/bin/run-all-tests.sh X 1

As in the single-contract case, no transformations and optimization testing are
possible by using a mutations count argument of 0 or "optimize", respectively.


### Test process

A large generated or externally supplied contract set can be executed using the
run-all-tests.sh script to find test cases that are flagged as potential bugs. There
are currently no known false positives in the test framework, so detected issues are 
more likely to point to compilation or execution errors than test framework errors.

There is currently no support for automated test case reduction. The manual test 
case reduction process may involve editing the transactions file test.js: remove 
"logEvents(instance...)" transactions and re-run the test until the problem disappears 
to pinpoint the *first* faulty contract function.

Note that transactions should be removed from the bottom first, since earlier
transactions change the initial program state for later transactions, which may
cause many assumptions during code generation to become invalid. So in a transaction
list like:

         logEvents(instance.f0());
         logEvents(instance.f1());
         logEvents(instance.f2());
         logEvents(instance.f3());

It would be desirable to comment out the second half - f2 and f3 - first, and proceed 
to comment out f1 afterwards if the problem remains.

Once the first faulty contract function has been identified, it can be reduced by
commenting out its code - again starting at the bottom and working to the top. Once
the first faulty program statement has been identified, the values of variables it
works on can be obtained by defining and emitting events that pass these values to
the event log file (described in the [input and results](#input-and-results) section. 
It would then also be possible to remove earlier statements and functions, and work
with assigned hardcoded values obtained from these events.

Finally, the faulty statement must be reduced, e.g. by replacing a sub-expression
involving an operator with the expected computational result of that operator, based
on the knowledge about the variable values obtained e.g. from emit statements.

# Known limitations

Only a comparatively small Solidity language subset is currently supported. This
includes expressions and control structures, but is missing various types and
operations, as well as more advanced contract structures like modifiers or
inheritance, and Ethereum-specific functionality like value transfer.

All components - ECTF, solc and truffle - exhibit performance issues for contracts
exceeding a few 100 or 1000 lines, and may fail completely. Experimentation is
needed to find sensible upper limits on a given system.

It is currently only possible to use truffle/ganache-cli as execution platform,
which poses two problems:

1. ganache-cli crashes on various exponentiation and shift operations, which
motivates the settings.cfg.sh options to disable their use completely by default
2. Other execution platforms, e.g. based on aleth, do not benefit from the test
process


# Technical details

This section gives an overview to some of the workings of the framework. The system
is composed of three categories of components:

1. The ECTF application to generate code
2. Third-party software: solc as a test object, truffle/ganache-cli as an execution backend
3. Shell scripts (described in the [use](#use) section above) to invoke the ECTF and third-party
components, and drive result evaluation



## Contract behavior

We define the behavior of a contract primarily as the set of values assumed by
its storage variables after having executed a set of transactions. An outro function
to be called by the transactions file is generated and inserted into the contract in 
order to _emit_ events that transmit variable values to the event log file. The
type, order and values of emitted user-defined events is also stored in the event
log and part of the behavior, which only affects externally supplied contracts that
emit events.

While compilers are often tested using _differential testing_ - i.e. comparing the
behavior of multiple compiler implementations to find divergences and thus
problems -, this is not applicable for Solidity language, which currently only
has the solc compiler. Instead, the following comparisons are possible:

1. Compare original contracts to semantically-equivalent contracts (described in the
[Semantically-equivalent transformations](#live-emi-transformation) section below)
2. Compare one contract with optimized compilation against itself with unoptimized
compilation (mentioned in the "Use" section above)
3. Built-in correctness checks in AS programs (described in the [contract generation](#contract-generation) section
 below)

## Contract generation

Most contract generation facilities are largely based on the expression and statement
generation functions and the "speculative execution" expression evaluation required by
the semantically equivalent mutations described below.

Assignment sequence programs are notably generated and interpreted at once, which
enables the introduction of a built-in differential testing function. This is enabled
by their structure, which at its core is a list of assignment expressions:

        var1 = expr1;
        var2 = expr2;
        ...

The expression evaluator, then, can evaluate the expressions in the order in which
they are generated - with a variable environment that is updated in accordance with
the assignments as well -, giving reference values known at compile time to compare
with the runtime result generated by compiled code. An error event is emitted to
signal divergences:

        var1 = expr1;
        if (var1 != evaluated_expr1_result)
            emit ERROR_EXPR(1);
        var2 = expr2;
        if (var2 != evaluated_expr2_result)
            emit ERROR_EXPR(2);

Invalid expressions are avoided by detecting their presence during the evaluation and
adapting it to make it valid, and the knowledge of expected values is recorded to
simulate the profiling step for semantically-equivalent mutations and thus enable the immediate
mutation generation without intervening profiling step.

In contrast, "complete" contracts are not evaluated during generation. For this reason,
expressions generated for such contracts are forced to be safe to execute by wrapping
operands, e.g. avoiding a division by zero in "x / y" by generating "x / (y != 0? y: z)"
instead. Additionally, loop limitations of the form "if (++counter > 2) break;" are
inserted both in generated as well as externally supplied contracts to ensure proper
termination of deeply nested loops and otherwise infinite loops.

## Semantically-equivalent transformation

Conceptually, the semantically-equivalent transformation process takes an input smart contract and
produces various variants from it. These should be semantically equivalent as per the
Solidity language definition, but could provoke compiler or execution bugs leading to
unexpected semantics. This is accoplished by synthesizing and inserting random code
snippets (mutations) into the program that should amount to no-op operations - program 
state can be changed temporarily within a snippet, but is always restored at the end of 
the snippet. The variants can potentially exercise many constellations in a compiler's
program analysis components on data flow and control flow, as well as resource
allocation (e.g. registers in traditional computer architectures).

The semantically-equivalent mutations are based on the ideas described in
["Finding  Compiler  Bugs  via  Live  Code  Mutation" (Sun et al., 2014)](http://web.cs.ucdavis.edu/~su/publications/oopsla16.pdf),
with various adaptations. They motivate the development of significant infrastructure to
profile smart contract execution (in the "profiling" package) and evaluate expressions
(in the "interpretation" package). The three described mutation types are implemented
with only minor technical divergences (in the "mutation" package) from their original
description.

Algorithmic extensions were required to enable the application of binary operators
to expressions of incompatible types: type conversions are applied where needed, with
the conditional operator providing a conversion pathway between types T1 and T2 without
direct conversion - "T1(expr)? T2(expr2): T2(expr3)", with randomly generated expr2 and
expr3 values -, and converting structure values to elementary types by accessing a
random member as a representative replacement value.

To process side effects in ++ and -- operators, the expression is not evaluated as it 
is built, but only once it has been fully constructed. This is needed to know whether 
a sub-expression involving side effects is actually evaluated, since it could also be 
an operand in a short-circuiting ||, && or ?: context. Function calls are simulated 
using the expression evaluator by realizing them as hidden sub-expressions for their 
evaluation, which are emitted as argument to a single "return" statement in the 
Solidity code output to implement the called function.

The profiling step is implemented by emitting events to transmit variable state to
the event log file, which can then be read into the ECTF application - along with the
original contract - to produce the mutated programs. As mentioned earlier, this only
pertains to "complete" contracts, since assignment sequence program mutations are created
in the same iteration as the original contract because its expected semantics are
already known and require no additional profiling step.

