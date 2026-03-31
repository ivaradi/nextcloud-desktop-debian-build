#!/bin/bash

set -e -u -x

scriptdir="$(readlink -f "$(dirname "${0}")")"

WORKSPACE="${1}"
BRANCH_TYPE="${2:-stable}"
REPOSITORY="${3:-https://github.com/nextcloud/desktop}"

if test "${BRANCH_TYPE}" = "stable"; then
    branch="${BRANCH_STABLE}"
elif test "${BRANCH_TYPE}" = "next-stable"; then
    branch="${BRANCH_NEXT_STABLE}"
else
    echo "Invalid branch type: ${BRANCH_TYPE}"
    exit 1
fi

case "${branch}" in
    stable-*)
        baseversion=$(echo "${branch}" | sed 's:stable-::')
        pattern="v${baseversion}.*"
        ;;
    *)
        echo "Cannot determine base version from ${branch}"
        exit 2
esac

tag=$(git ls-remote --refs --tags "${REPOSITORY}" "${pattern}" \
          | awk '{print $2}' \
          | sed 's:refs/tags/::' \
          | python3 -c "
import sys, re
from packaging import version
tags = sys.stdin.read().strip().split('\n')
tags.sort(key=lambda t: version.parse(t.lstrip('v')))
for tag in tags: print(tag)
" | tail -n 1)

if ! curl --fail "${REPOSITORY}/releases/tags/${tag}"; then
    echo "No release for tag ${tag} yet, skipping"
    exit 0
fi

commitfiledir="${scriptdir}/commits"
tagfile="${commitfiledir}/latest-tag-${branch}"

if test ! -f "${tagfile}" -o "${tag}" != "$(cat "${tagfile}")"; then
    "${scriptdir}/debian-build.sh" "${WORKSPACE}" \
                                   "${tag}" \
                                   "${branch}" "${BRANCH_TYPE}" \
                                   "${REPOSITORY}" "tag"

    mkdir -p "${commitfiledir}"
    echo "${tag}" > "${tagfile}"
    git -C "${scriptdir}" add "${tagfile}"
    git -C "${scriptdir}" commit \
        --message "Updated latest tag for branch ${branch}" \
        "${tagfile}"

    attempts=3
    while ! git -C "${scriptdir}" push; do
        if test ${attempts} -le 0; then
            exit 1
        fi
        attempts=$((attempts - 1))
        git -C "${scriptdir}" pull --rebase
    done
fi
