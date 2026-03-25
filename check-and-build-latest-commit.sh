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

if test ! -f "${commitfile}" -o "${commit}" != "$(cat "${commitfile}")"; then
    "${scriptdir}/debian-build.sh" "${WORKSPACE}" \
                                   "${commit}" \
                                   "${branch}" "${BRANCH_TYPE}" \
                                   "${REPOSITORY}"

    mkdir -p "${commitfiledir}"
    echo "${commit}" > "${commitfile}"
    git -C "${scriptdir}" add "${commitfile}"
    git -C "${scriptdir}" commit \
        --message "Updated latest commit for branch ${branch}" \
        "${commitfile}"
    git -C "${scriptdir}" push
fi
