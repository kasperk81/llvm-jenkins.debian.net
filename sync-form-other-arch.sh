#!/bin/bash
set -e

if test $# -ne 3; then
    echo "error"
    echo "syntax $0 DISTRO HOST ARCH"
    exit 1
fi

reprepro --version
dpkg -l reprepro

DISTRO=$1
HOST=$2
ARCH=$3


declare -a old_versions=("9" "10" "11" "12" "13" "14" "15")

for version in "${old_versions[@]}"
do
    excludes+=(--exclude "pool/main/l/llvm-toolchain-$version/" --exclude "dists/llvm-toolchain-$DISTRO-$version/")
done
echo "Ignore ${excludes[@]}"

rsync -avzh --delete "${excludes[@]}" jenkins@$HOST:/srv/repository/$DISTRO/ /tmp/tmp-$DISTRO/
if ! test -d /tmp/tmp-$DISTRO/pool/main/; then
        echo "Distro $DISTRO not existing yet"
        exit 0
fi


versions=("15" "16" "17" "18" "")
for ver in "${versions[@]}"; do

    declare -A src_pkg_versions
    declare -A dst_pkg_versions
    if test "$DISTRO" != "unstable"; then
        base_dist="-$DISTRO"
    else
        base_dist=""
    fi
    dist="llvm-toolchain${base_dist}${ver:+-}$ver"
    echo $dist

    remote_packages=$(reprepro -b /tmp/tmp-$DISTRO/ list "$dist" | grep "$ARCH" | awk '{print $2,$3}')
    while read -r line; do
        pkg=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        if [[ -n "$pkg" ]]; then
            src_pkg_versions["$pkg"]=$ver
        fi
    done <<< "$remote_packages"
    echo "Number packages coming from $ARCH: ${#src_pkg_versions[@]}"
    echo "To see the list: reprepro -b /tmp/tmp-$DISTRO/ list '$dist'"

    repo_packages=$(reprepro -b /srv/repository/$DISTRO/ list "$dist" | grep "amd64" | awk '{print $2,$3}')
    while read -r line; do
        pkg=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        if [[ -n "$pkg" ]]; then
            dst_pkg_versions["$pkg"]=$ver
        fi
    done <<< "$repo_packages"
    echo "Number of local amd64 packages: ${#src_pkg_versions[@]}"
    echo "To see the list: reprepro -b /srv/repository/$DISTRO/ list '$dist'"

    for pkg in "${!src_pkg_versions[@]}"; do
        if [[ -n "${dst_pkg_versions[$pkg]}" && "${src_pkg_versions[$pkg]}" != "${dst_pkg_versions[$pkg]}" ]]; then
            echo "error: $pkg has different versions for $ARCH: ${src_pkg_versions[$pkg]} vs ${dst_pkg_versions[$pkg]}"
	    echo -n "build id: "
            echo -n ${src_pkg_versions[$pkg]} | awk -F"." '{printf "%s", $2}'
            echo -n " / "
            echo ${dst_pkg_versions[$pkg]} | awk -F"." '{print $2}'
	    #            exit 1
        fi
    done
done
echo "=== version check completed ==="

for f in /tmp/tmp-$DISTRO/dists/llvm-*/main/binary-$ARCH/; do
    echo "f= $f"
    echo "DISTRO = $DISTRO"
    VERSION=$(echo "$f" | sed -E -e "s|/tmp/tmp-$DISTRO/dists/llvm-toolchain(-$DISTRO)?-?([[:digit:]]+)/.*|\2|g")
    echo "VERSION $VERSION"
    re='^[0-9]+$'

    # Skip if version is in versions array
    if [[ " ${old_versions[*]} " == *" $VERSION "* ]]; then
        echo "Skipping old version $VERSION"
        continue
    fi

    if ! [[ $VERSION =~ $re ]] ; then
            # maybe debian unstable
            VERSION=$(echo $f|sed -e "s|/tmp/tmp-$DISTRO/dists/llvm-toolchain-\([[:digit:]]\+\)/.*|\1|g")
            if ! [[ $VERSION =~ $re ]] ; then
                echo "Probably the nightly version"
                break
            fi
    fi
    # Workaround: don't import libclc (provided by amd64)
    # checksum differences otherwise
    rm -f /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain*/libclc-*deb

    # Second workaround to remove _all packages
    rm -f /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain*/*_all.deb

    # Import of the stable and stabilisation version
    if test $DISTRO == "unstable"; then
        reprepro -Vb /srv/repository/$DISTRO/ includedeb llvm-toolchain-$VERSION /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-$VERSION/*deb
    else
	echo reprepro -Vb /srv/repository/$DISTRO/ includedeb llvm-toolchain-$DISTRO-$VERSION /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-$VERSION/*deb
        reprepro -Vb /srv/repository/$DISTRO/ includedeb llvm-toolchain-$DISTRO-$VERSION /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-$VERSION/*deb
    fi
done

# Import of the nightly builds

if test -d /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain/ -o -d /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-snapshot/; then
    if test $DISTRO == "unstable"; then
        reprepro -Vb /srv/repository/$DISTRO/ includedeb llvm-toolchain /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-snapshot/*deb
    else
        reprepro -Vb /srv/repository/$DISTRO/ includedeb llvm-toolchain-$DISTRO /tmp/tmp-$DISTRO/pool/main/l/llvm-toolchain-snapshot/*deb
    fi
fi
