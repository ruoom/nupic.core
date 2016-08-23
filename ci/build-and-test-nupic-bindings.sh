#!/bin/bash
# ----------------------------------------------------------------------
# Numenta Platform for Intelligent Computing (NuPIC)
# Copyright (C) 2016, Numenta, Inc.  Unless you have purchased from
# Numenta, Inc. a separate commercial license for this software code, the
# following terms and conditions apply:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU Affero Public License for more details.
#
# You should have received a copy of the GNU Affero Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# http://numenta.org/licenses/
# ----------------------------------------------------------------------

set -o errexit


USAGE="Usage:

[BUILD_TYPE=Release | Debug] [RESULT_KEY=key-string] [WHEEL_PLAT=platform] $( basename ${0} )

This script builds and tests the nupic.bindings Python extension.

In Debug builds, also
  - Turns on the Include What You Use check (assumes iwyu is installed)

ASUMPTION: Expects a pristine nupic.core source tree without any remnant build
   artifacts from prior build attempts. Otherwise, behavior is undefined.


INPUT ENVIRONMENT VARIABLES:

  BUILD_TYPE : Specifies build type, which may be either Release or Debug;
               defaults to Release. [OPTIONAL]
  RESULT_KEY : Build result key; used to decorate artifact names. [OPTIONAL]
  WHEEL_PLAT : Wheel platform name; pass manylinux1_x86_64 for manylinux build;
               leave undefined for all other builds.

OUTPUTS:
  nupic.bindings wheel: On success, the resulting wheel will be located in the
                        subdirectory nupic_bindings_wheelhouse of the source
                        tree's root directory.

  test results: nupic.bindings test results will be located in the subdirectory
                test_results of the source tree's root directory with the
                the following content:

                cplusplus-test-results.txt
                junit-test-results.xml
                htmlcov-report/

"

if [[ $1 == --help ]]; then
  echo "${USAGE}"
  exit 0
fi

if [[ $# > 0 ]]; then
  echo "ERROR Unexpected arguments: ${@}" >&2
  echo "${USAGE}" >&2
  exit 1
fi


set -o xtrace


# Apply defaults
BUILD_TYPE=${BUILD_TYPE-"Release"}


NUPIC_CORE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

DEST_WHEELHOUSE="${NUPIC_CORE_ROOT}/nupic_bindings_wheelhouse"

TEST_RESULTS_DIR="${NUPIC_CORE_ROOT}/test_results"

echo "RUNNING NUPIC BINDINGS BUILD: BUILD_TYPE=${BUILD_TYPE}, " \
     "RESULT_KEY=${RESULT_KEY}, DEST_WHEELHOUSE=${DEST_WHEELHOUSE}" >&2

# Install pycapnp to get the matching capnproto headers for nupic.core build
# NOTE Conditional pycapnp dependency should be incorporated into
# bindings/py/requirements.txt to abstract it from upstream scripts.
pip install pycapnp==0.5.8

# Install nupic.bindings dependencies; the nupic.core cmake build depends on
# some of them (e.g., numpy).
pip install -r ${NUPIC_CORE_ROOT}/bindings/py/requirements.txt


#
# Build nupic.bindings
#

# ZZZ debug statement to see if build/scripts was inherited from another job
ls ${NUPIC_CORE_ROOT}/build/scripts || true
# ZZZ end debug

mkdir -p ${NUPIC_CORE_ROOT}/build/scripts
cd ${NUPIC_CORE_ROOT}/build/scripts

# Configure nupic.core build
if [[ "$BUILD_TYPE" == "Debug" ]]; then
  EXTRA_CMAKE_DEFINITIONS="-DNUPIC_IWYU=ON -DNTA_COV_ENABLED=ON"
fi

cmake ${NUPIC_CORE_ROOT} \
    -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
    ${EXTRA_CMAKE_DEFINITIONS} \
    -DCMAKE_INSTALL_PREFIX=${NUPIC_CORE_ROOT}/build/release \
    -DPY_EXTENSIONS_DIR=${NUPIC_CORE_ROOT}/bindings/py/nupic/bindings

# Build nupic.core
make install

# Build nupic.bindings python extensions from nupic.core build artifacts
if [[ $WHEEL_PLAT ]]; then
  EXTRA_WHEEL_OPTIONS="--plat-name ${WHEEL_PLAT}"
fi

cd ${NUPIC_CORE_ROOT}
python setup.py bdist_wheel --dist-dir ${DEST_WHEELHOUSE} ${EXTRA_WHEEL_OPTIONS}


#
# Test
#

# ZZZ debug statement to see if test_results was inherited from another job
ls -R ${TEST_RESULTS_DIR} || true
# ZZZ end debug

mkdir ${TEST_RESULTS_DIR}

# Install the wheel that we just built
pip install --ignore-installed ${DEST_WHEELHOUSE}/nupic.bindings-*.whl

# Run the nupic.core C++ tests
cd ${NUPIC_CORE_ROOT}/build/release/bin
(
  ./connections_performance_test
  ./cpp_region_test
  ./helloregion
  ./hello_sp_tp
  ./prototest
  ./py_region_test
  ./unit_tests
) 2>&1 | tee "${TEST_RESULTS_DIR}/cplusplus-test-results.txt"


py.test --verbose \
  --junitxml \
    "${TEST_RESULTS_DIR}/junit-test-results.xml" \
  --cov nupic.bindings \
  --cov-report html \
  ${NUPIC_CORE_ROOT}/bindings/py/tests

mv ./htmlcov ${TEST_RESULTS_DIR}/htmlcov-report

# ZZZ Debug statement to see the final contents of test_results
ls -R ${TEST_RESULTS_DIR}
# ZZZ End debug
