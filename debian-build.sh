#!/bin/bash

set -e -x -u
shopt -s extglob

scriptdir="$(readlink -f "$(dirname "${0}")")"

WORKSPACE="${1}"
COMMIT="${2}"
BRANCH="${3:-master}"
BRANCH_TYPE="${4:-master}"
REPOSITORY="${5:-https://github.com/nextcloud/desktop}"

PPA=ppa:nextcloud-devs/client
PPA_ALPHA=ppa:nextcloud-devs/client-alpha
PPA_BETA=ppa:nextcloud-devs/client-beta

OBS_PROJECT=home:ivaradi
OBS_PROJECT_ALPHA=home:ivaradi:alpha
OBS_PROJECT_BETA=home:ivaradi:beta
OBS_PROJECT_STABLE_ALPHA=home:ivaradi:stable-alpha
OBS_PROJECT_NEXT_STABLE_ALPHA=home:ivaradi:next-stable-alpha

UBUNTU_DISTRIBUTIONS="jammy noble questing resolute"
DEBIAN_DISTRIBUTIONS="bookworm trixie testing"

declare -A DIST_TO_OBS=(
    ["jammy"]="xUbuntu_22.04"
    ["noble"]="xUbuntu_24.04"
    ["questing"]="xUbuntu_25.10"
    ["resolute"]="xUbuntu_26.04"
    ["bookworm"]="Debian_12"
    ["trixie"]="Debian_13"
    ["testing"]="Debian_Testing"
)

set +x
has_ppa_keys="no"
if test "${DEBIAN_SECRET_KEY:-}" -a "${DEBIAN_SECRET_IV:-}"; then
    openssl aes-256-cbc -K "${DEBIAN_SECRET_KEY}" -iv "${DEBIAN_SECRET_IV}" -in "${scriptdir}/signing-key.txt.enc" -d | gpg --import

    openssl aes-256-cbc -K "${DEBIAN_SECRET_KEY}" -iv "${DEBIAN_SECRET_IV}" -in "${scriptdir}/oscrc.enc" -out ~/.oscrc -d

    has_ppa_keys="yes"
fi
set -x

cd "${WORKSPACE}"

rm -rf nextcloud-desktop
mkdir -p nextcloud-desktop
cd nextcloud-desktop

git init .
git remote add origin "${REPOSITORY}"
git fetch origin "${COMMIT}"
git checkout FETCH_HEAD

for distribution in ${UBUNTU_DISTRIBUTIONS} ${DEBIAN_DISTRIBUTIONS}; do
    git clean -xdff
    git -C "${scriptdir}" archive --format=tar \
        "debian/dist/${distribution}/${BRANCH}" | \
        tar --extract

    read -r basever revdate kind <<<"$("${scriptdir}/git2changelog.py" \
                                               /tmp/tmpchangelog git2changelog.cfg \
                                               stable ""  "" "${COMMIT}")"
    break
done

cd "${WORKSPACE}"

echo "$kind" > kind

mv nextcloud-desktop "nextcloud-desktop_${basever}-${revdate}"
tar cjf "nextcloud-desktop_${basever}-${revdate}.orig.tar.bz2" \
    --exclude .git --exclude binary \
    "nextcloud-desktop_${basever}-${revdate}"

cd "${WORKSPACE}/nextcloud-desktop_${basever}-${revdate}"

for distribution in ${UBUNTU_DISTRIBUTIONS} ${DEBIAN_DISTRIBUTIONS}; do
    git checkout -- .
    git clean -xdff

    git -C "${scriptdir}" archive --format=tar \
        "debian/dist/${distribution}/${BRANCH}" | \
        tar --extract

    "${scriptdir}//git2changelog.py" /tmp/tmpchangelog git2changelog.cfg \
                                     "${distribution}" "${revdate}" "${basever}"
    cat /tmp/tmpchangelog debian/changelog > debian/changelog.new
    mv debian/changelog.new debian/changelog

    fullver=$(head -1 debian/changelog | sed "s:nextcloud-desktop (\([^)]*\)).*:\1:")

    EDITOR=true dpkg-source --commit . local-changes

    dpkg-source --build .
    dpkg-genchanges -S -sa > "../nextcloud-desktop_${fullver}_source.changes"

    if test "${has_ppa_keys}" = "yes"; then
        debsign -k2265D8767D14AA7B -S
    fi
done
cd ..
ls -al

if test "${BRANCH_TYPE}" = "master"; then
    PPA_DISTRIBUTIONS="${UBUNTU_DISTRIBUTIONS}"
    OBS_DISTRIBUTIONS="${DEBIAN_DISTRIBUTIONS}"
    if test "$kind" = "alpha"; then
        PPA=$PPA_ALPHA
        OBS_PROJECT=$OBS_PROJECT_ALPHA
    elif test "$kind" = "beta"; then
        PPA=$PPA_BETA
        OBS_PROJECT=$OBS_PROJECT_BETA
    fi
else
    PPA_DISTRIBUTIONS=""
    OBS_DISTRIBUTIONS="${UBUNTU_DISTRIBUTIONS} ${DEBIAN_DISTRIBUTIONS}"
    if test "${BRANCH_TYPE}" = "stable"; then
        OBS_PROJECT="${OBS_PROJECT_STABLE_ALPHA}"
    else
        OBS_PROJECT="${OBS_PROJECT_NEXT_STABLE_ALPHA}"
    fi
fi



if test "${has_ppa_keys}" = "yes"; then
    for distribution in ${PPA_DISTRIBUTIONS}; do
        changes=$(ls -1 nextcloud-desktop_*"~${distribution}1_source.changes")
        if test -f "${changes}"; then
            dput $PPA "${changes}" > /dev/null
        fi
    done

    if test -n "${OBS_DISTRIBUTIONS}"; then
        package="nextcloud-desktop"
        OBS_SUBDIR="${OBS_PROJECT}/${package}"

        rm -rf osc
        mkdir -p osc
        pushd osc
        osc co "${OBS_PROJECT}" "${package}"

        if test "$(ls ${OBS_SUBDIR})"; then
            osc delete ${OBS_SUBDIR}/*
        fi

        ln ../nextcloud-desktop*.orig.tar.* ${OBS_SUBDIR}/

        for distribution in ${DEBIAN_DISTRIBUTIONS}; do
            pkgvertag="~${distribution}1"
            obs_dist="${DIST_TO_OBS[${distribution}]}"

            ln ../nextcloud-desktop_*[0-9.][0-9]"${pkgvertag}.dsc" "${OBS_SUBDIR}/nextcloud-desktop-${obs_dist}.dsc"
            ln ../nextcloud-desktop_*[0-9.][0-9]"${pkgvertag}.debian.tar"* "${OBS_SUBDIR}/"
        done

        osc add ${OBS_SUBDIR}/*

        cd ${OBS_SUBDIR}
        osc commit -m "Drone update"
        popd
    fi
fi
