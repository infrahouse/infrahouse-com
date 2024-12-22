#!/usr/bin/env bash

set -eux


function generate_changelog() {
  cat > debian/changelog << EOF
infrahouse-com (0.2.0-1build$(date +%s)) jammy; urgency=medium
  * commit event. see changes history in git log

 -- InfraHouse Packager <package@infrahouse.com>  $(date)

EOF
}
generate_changelog

upstream_version=$(head -1 debian/changelog | awk '{ print $2 }' | sed -e 's/[()]//g' | awk -F- '{ print $1 }')
pkg_name="infrahouse-com"
TMPDIR=$(mktemp -d)

DEBEMAIL=${DEBEMAIL-packager@infrahouse.com}
DEBFULLNAME=${DEBFULLNAME-InfraHouse Packager}

cleanup () {
  rm -rf "${TMPDIR}"
}

trap cleanup ERR
trap cleanup EXIT

mkdir "${TMPDIR}/${pkg_name}_${upstream_version}"
cp -R public/* "${TMPDIR}/${pkg_name}_${upstream_version}"

tar zcf "../${pkg_name}_${upstream_version}.orig.tar.gz" -C "${TMPDIR}" "${pkg_name}_${upstream_version}"
debuild --build=all -us -uc
