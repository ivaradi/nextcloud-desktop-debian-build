#!/bin/bash

set -e -u -x

scriptdir="$(readlink -f "$(dirname "${0}")")"

WORKSPACE="${1}"
BRANCH_TYPE="${2:-master}"
REPOSITORY="${3:-https://github.com/nextcloud/desktop}"

if test "${BRANCH_TYPE}" = "master"; then
    branch="master"
elif test "${BRANCH_TYPE}" = "stable"; then
    branch="${BRANCH_STABLE}"
elif test "${BRANCH_TYPE}" = "next-stable"; then
    branch="${BRANCH_NEXT_STABLE}"
else
    echo "Invalid branch type: ${BRANCH_TYPE}"
    exit 1
fi

commit=$(git ls-remote "${REPOSITORY}" "refs/heads/${branch}" |
             awk '{print $1}')

commitfiledir="${scriptdir}/commits"
commitfile="${commitfiledir}/latest-commit-${branch}"
if test -f "${commitfile}"; then
    exists="yes"
else
    exists="no"
fi

if test "${exists}" = "no" -o "${commit}" != "$(cat "${commitfile}")"; then
    mkdir -p "${commitfiledir}"
    echo "${commit}" > "${commitfile}"
    if test "${exists}" = "no"; then
        git -C "${scriptdir}" add "${commitfile}"
    fi
    git -C "${scriptdir}" commit -a -m "Updated latest commit for branch ${branch}"
    git -C "${scriptdir}" push

    "${scriptdir}/debian-build.sh" "${WORKSPACE}" \
                                   "${commit}" "${branch}" "${REPOSITORY}"
fi
