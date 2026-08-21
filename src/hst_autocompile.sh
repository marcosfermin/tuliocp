#!/bin/bash

# set -e
# Autocompile Script for TulioCP package Files.
# For building from local source folder use "~localsrc" keyword as hesia branch name,
#   and the script will not try to download the arhive from github, since '~' char is
#   not accepted in branch name.
# Compile but dont install -> ./hst_autocompile.sh --tulio --noinstall --keepbuild '~localsrc'
# Compile and install -> ./hst_autocompile.sh --tulio --install '~localsrc'

# Clear previous screen output
clear

# Define download function
download_file() {
	local url=$1
	local destination=$2
	local force=$3

	if [ -z "$(which "wget")" ]; then
		echo "Installing wget..."
		apt-get -qq update > /dev/null
		apt-get -qq install -y wget
	fi

	[ "$TULIO_DEBUG" ] && echo >&2 DEBUG: Downloading file "$url" to "$destination"

	# Default destination is the current working directory
	local dstopt=""

	if [ ! -z "$(echo "$url" | grep -E "\.(gz|gzip|bz2|zip|xz)$")" ]; then
		# When an archive file is downloaded it will be first saved localy
		dstopt="--directory-prefix=$ARCHIVE_DIR"
		local is_archive="true"
		local filename="${url##*/}"
		if [ -z "$filename" ]; then
			echo >&2 "[!] No filename was found in url, exiting ($url)"
			exit 1
		fi
		if [ ! -z "$force" ] && [ -f "$ARCHIVE_DIR/$filename" ]; then
			rm -f $ARCHIVE_DIR/$filename
		fi
	elif [ ! -z "$destination" ]; then
		# Plain files will be written to specified location
		dstopt="-O $destination"
	fi
	# check for corrupted archive
	if [ -f "$ARCHIVE_DIR/$filename" ] && [ "$is_archive" = "true" ]; then
		tar -tzf "$ARCHIVE_DIR/$filename" > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo >&2 "[!] Archive $ARCHIVE_DIR/$filename is corrupted, redownloading"
			rm -f $ARCHIVE_DIR/$filename
		fi
	fi

	if [ ! -f "$ARCHIVE_DIR/$filename" ]; then
		[ "$TULIO_DEBUG" ] && echo >&2 DEBUG: wget $url -q $dstopt --show-progress --progress=bar:force --limit-rate=3m
		wget $url -q $dstopt --show-progress --progress=bar:force --limit-rate=3m
		if [ $? -ne 0 ]; then
			echo >&2 "[!] Archive $ARCHIVE_DIR/$filename is corrupted and exit script"
			rm -f $ARCHIVE_DIR/$filename
			exit 1
		fi
	fi

	if [ ! -z "$destination" ] && [ "$is_archive" = "true" ]; then
		if [ "$destination" = "-" ]; then
			cat "$ARCHIVE_DIR/$filename"
		elif [ -d "$(dirname $destination)" ]; then
			cp "$ARCHIVE_DIR/$filename" "$destination"
		fi
	fi
}

get_branch_file() {
	local filename=$1
	local destination=$2
	[ "$TULIO_DEBUG" ] && echo >&2 DEBUG: Get branch file "$filename" to "$destination"
	if [ "$use_src_folder" == 'true' ]; then
		if [ -z "$destination" ]; then
			[ "$TULIO_DEBUG" ] && echo >&2 DEBUG: cp -f "$SRC_DIR/$filename" ./
			cp -f "$SRC_DIR/$filename" ./
		else
			[ "$TULIO_DEBUG" ] && echo >&2 DEBUG: cp -f "$SRC_DIR/$filename" "$destination"
			cp -f "$SRC_DIR/$filename" "$destination"
		fi
	else
		# TODO(tulio): infrastructure not yet deployed
		download_file "https://raw.githubusercontent.com/$REPO/$branch/$filename" "$destination" $3
	fi
}

usage() {
	echo "Usage:"
	echo "    $0 (--all|--tulio|--nginx|--php|--web-terminal) [options] [branch] [Y]"
	echo ""
	echo "    --all           Build all tulio packages."
	echo "    --tulio        Build only the Control Panel package."
	echo "    --nginx         Build only the backend nginx engine package."
	echo "    --php           Build only the backend php engine package"
	echo "    --web-terminal  Build only the backend web terminal websocket package"
	echo "  Options:"
	echo "    --install       Install generated packages"
	echo "    --keepbuild     Don't delete downloaded source and build folders"
	echo "    --cross         Compile tulio package for both AMD64 and ARM64"
	echo "    --debug         Debug mode"
	echo "    --pkgrev <n>    Set the package revision number (default: 1)."
	echo "                    Replaces the '-1' in the version suffix"
	echo "                    (e.g. --pkgrev 2 → 1.0.0-2+deb12)."
	echo "    --release <id>  Set a release identifier appended to the package version"
	echo "                    as '~<id>' (e.g. --release myci1 → 1.0.0-1+deb12~myci1)."
	echo "                    Useful to distinguish custom or CI builds from official ones."
	echo "                    If the tulio control file's Version already has a '~<tag>'"
	echo "                    suffix (e.g. 1.1.0~alpha) and --release is NOT given, that"
	echo "                    detected tag (e.g. 'alpha') is used automatically as the"
	echo "                    release identifier for ALL packages. If --release IS given,"
	echo "                    it overrides/replaces the detected '~<tag>' suffix instead."
	echo "                    Can be combined: --pkgrev 2 --release myci1 → 1.0.0-2+deb12~myci1."
	echo ""
	echo "For automated builds and installations, you may specify the branch"
	echo "after one of the above flags. To install the packages, specify 'Y'"
	echo "following the branch name."
	echo ""
	echo "Example: bash hst_autocompile.sh --tulio develop Y"
	echo "This would install a Tulio Control Panel package compiled with the"
	echo "develop branch code."
	echo ""
	echo "To cross-build tulio-nginx/tulio-php/tulio-web-terminal for the other"
	echo "architecture, or for other OS releases, on the same machine, use"
	echo "./chroot_build_all.sh instead."
}

get_distro_suffix() {
	local distro_id distro_num
	distro_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
	distro_num=$(lsb_release -rs)

	if [ "$distro_id" = "debian" ]; then
		echo "debian${distro_num}"
	elif [ "$distro_id" = "ubuntu" ]; then
		echo "ubuntu${distro_num}"
	else
		echo "unknown"
	fi
}

apply_distro_version() {
	local control_file="$1"
	local distro_suffix="$2"
	if [ -z "$distro_suffix" ]; then
		distro_suffix=$(get_distro_suffix)
	fi

	local current_version
	current_version=$(grep "^Version:" "$control_file" | awk '{print $2}')

	# Strip any existing '~<tag>' pre-release suffix (e.g. ~alpha, ~beta, ~rc1) from the
	# base version before reconstructing it below. The tag itself (if present) was already
	# captured globally as BUILD_RELEASE (see BUILD_VER handling), unless the user passed
	# --release explicitly, in which case BUILD_RELEASE holds the user-specified value.
	local base_version="$current_version"
	if echo "$current_version" | grep -qE '~'; then
		base_version=$(echo "$current_version" | sed -E 's/~.*$//')
	fi

	# Build the release suffix:
	#   - Default pkgrev is 1; override with --pkgrev <n>
	#   - Without a release id : -<pkgrev>+<distro_suffix>                (e.g. -1+debian12)
	#   - With    a release id : -<pkgrev>+<distro_suffix>~<BUILD_RELEASE> (e.g. -1+debian12~myci1)
	# BUILD_RELEASE here may come from:
	#   1) the --release command line option (explicit user choice), or
	#   2) the '~<tag>' suffix auto-detected from the tulio control file's Version,
	#      when --release was NOT specified (see detection right after BUILD_VER is read).
	local pkg_rev="${BUILD_PKG_REV:-1}"
	local release_suffix="-${pkg_rev}+${distro_suffix}"
	if [ -n "$BUILD_RELEASE" ]; then
		release_suffix="${release_suffix}~${BUILD_RELEASE}"
	fi

	sed -i "s/^Version: \(.*\)/Version: ${base_version}${release_suffix}/" "$control_file"
}

# Detects the package that provides a shared library required by tulio-php
detect_pkg_from_elf() {
	local bin="$1"
	local lib_pattern="$2"

	local so_name
	so_name=$(readelf -d "$bin" 2> /dev/null \
		| awk '/NEEDED/ {gsub(/\[|\]/,"",$5); print $5}' \
		| grep "$lib_pattern" \
		| head -n1)

	[[ -z "$so_name" ]] && return 0

	# Try to resolve the real library path
	local so_path=""
	so_path=$(ldconfig -p 2> /dev/null \
		| awk -v lib="$so_name" '$1 == lib {print $NF; exit}')

	# Fallback if ldconfig does not return a result
	if [[ -z "$so_path" ]]; then
		so_path=$(find /lib /usr/lib -name "$so_name" 2> /dev/null | head -n1)
	fi

	[[ -z "$so_path" ]] && return 0

	# Use basename because dpkg-query expects only the file name, not the full path
	local pkg
	pkg=$(dpkg-query -S "$(basename "$so_path")" 2> /dev/null \
		| cut -d: -f1 \
		| head -n1)

	echo "$pkg"
}

# Set compiling directory
REPO='marcosfermin/tuliocp'
BUILD_DIR="${BUILD_DIR:-/tmp/tuliocp-src}"
INSTALL_DIR='/usr/local/tulio'
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_DIR="$SRC_DIR/src/archive/"
architecture="$(arch)"
if [ $architecture == 'aarch64' ]; then
	BUILD_ARCH='arm64'
else
	BUILD_ARCH='amd64'
fi

DEB_DIR="${DEB_DIR:-$BUILD_DIR/deb}"

# Set packages to compile
for i in $*; do
	case "$i" in
		--all)
			NGINX_B='true'
			PHP_B='true'
			WEB_TERMINAL_B='true'
			TULIO_B='true'
			;;
		--nginx)
			NGINX_B='true'
			;;
		--php)
			PHP_B='true'
			;;
		--web-terminal)
			WEB_TERMINAL_B='true'
			;;
		--tulio)
			TULIO_B='true'
			;;
		--debug)
			TULIO_DEBUG='true'
			;;
		--install | Y)
			install='true'
			;;
		--noinstall | N)
			install='false'
			;;
		--keepbuild)
			KEEPBUILD='true'
			;;
		--cross)
			CROSS='true'
			;;
		--help | -h)
			usage
			exit 1
			;;
		--dontinstalldeps)
			dontinstalldeps='true'
			;;
		--release)
			# Handled below via shift-style positional parsing; value captured next iteration
			_next_is_release='true'
			;;
		--pkgrev)
			# Handled below; value captured next iteration
			_next_is_pkgrev='true'
			;;
		*)
			if [ "$_next_is_release" = 'true' ]; then
				# Capture the value that follows --release
				BUILD_RELEASE="$i"
				RELEASE_EXPLICIT='true'
				unset _next_is_release
			elif [ "$_next_is_pkgrev" = 'true' ]; then
				# Capture the value that follows --pkgrev
				BUILD_PKG_REV="$i"
				unset _next_is_pkgrev
			else
				branch="$i"
			fi
			;;
	esac
done

if [[ $# -eq 0 ]]; then
	usage
	exit 1
fi

# Clear previous screen output
clear

# Set command variables
if [ -z $branch ]; then
	echo -n "Please enter the name of the branch to build from (e.g. main): "
	read branch
fi

if [ $(echo "$branch" | grep '^~localsrc') ]; then
	branch=$(echo "$branch" | sed 's/^~//')
	use_src_folder='true'
else
	use_src_folder='false'
fi

if [ -z $install ]; then
	echo -n 'Would you like to install the compiled packages? [y/N] '
	read install
fi

# Set Version for compiling
if [ -f "$SRC_DIR/src/deb/tulio/control" ] && [ "$use_src_folder" == 'true' ]; then
	BUILD_VER=$(cat $SRC_DIR/src/deb/tulio/control | grep "Version:" | cut -d' ' -f2)
	NGINX_V=$(cat $SRC_DIR/src/deb/nginx/control | grep "Version:" | cut -d' ' -f2)
	PHP_V=$(cat $SRC_DIR/src/deb/php/control | grep "Version:" | cut -d' ' -f2)
	WEB_TERMINAL_V=$(cat $SRC_DIR/src/deb/web-terminal/control | grep "Version:" | cut -d' ' -f2)
else
	# TODO(tulio): infrastructure not yet deployed
	BUILD_VER=$(download_file https://raw.githubusercontent.com/$REPO/$branch/src/deb/tulio/control | grep "Version:" | cut -d' ' -f2)
	# TODO(tulio): infrastructure not yet deployed
	NGINX_V=$(download_file https://raw.githubusercontent.com/$REPO/$branch/src/deb/nginx/control | grep "Version:" | cut -d' ' -f2)
	# TODO(tulio): infrastructure not yet deployed
	PHP_V=$(download_file https://raw.githubusercontent.com/$REPO/$branch/src/deb/php/control | grep "Version:" | cut -d' ' -f2)
	# TODO(tulio): infrastructure not yet deployed
	WEB_TERMINAL_V=$(download_file https://raw.githubusercontent.com/$REPO/$branch/src/deb/web-terminal/control | grep "Version:" | cut -d' ' -f2)
fi

if [ -z "$BUILD_VER" ]; then
	echo "Error: Branch invalid, could not detect version"
	exit 1
fi

# Auto-detect a '~<tag>' pre-release suffix (e.g. ~alpha, ~beta, ~rc1) from the tulio
# control file's Version. If the user did NOT explicitly pass --release on the command
# line, this detected tag becomes BUILD_RELEASE and will be propagated to ALL packages
# (nginx, php, web-terminal, tulio), even though those individual package versions
# don't carry the '~tag' themselves. If --release WAS explicitly given, it takes
# precedence and the detected tag is discarded (replaced) instead.
if echo "$BUILD_VER" | grep -qE '~'; then
	DETECTED_PRERELEASE_TAG=$(echo "$BUILD_VER" | sed -E 's/^[^~]*~//')
	if [ "$RELEASE_EXPLICIT" != 'true' ] && [ -n "$DETECTED_PRERELEASE_TAG" ]; then
		BUILD_RELEASE="$DETECTED_PRERELEASE_TAG"
	fi
fi

if [[ -n "$BUILD_RELEASE" ]]; then
	_build_release=" ($BUILD_RELEASE)"
fi
echo "Build version ${BUILD_VER}${_build_release}, with Nginx version $NGINX_V, PHP version $PHP_V and Web Terminal version $WEB_TERMINAL_V"

TULIO_V="${BUILD_VER}_${BUILD_ARCH}"
# List of supported OS releases for Tulio used for crossbuilding.
supported_os="debian11 debian12 debian13 ubuntu22.04 ubuntu24.04 ubuntu26.04"
OPENSSL_V='3.5.7'
PCRE_V='10.47'
ZLIB_V='1.3.2'

# Create build directories
if [ "$KEEPBUILD" != 'true' ]; then
	rm -rf $BUILD_DIR
fi
mkdir -p $BUILD_DIR
mkdir -p $DEB_DIR
mkdir -p $ARCHIVE_DIR

# Define a timestamp function
timestamp() {
	date +%s
}

if [ "$dontinstalldeps" != 'true' ]; then
	# Install needed software
	# Set package dependencies for compiling
	SOFTWARE='wget tar git curl ca-certificates build-essential libxml2-dev libz-dev libzip-dev libgmp-dev libcurl4-gnutls-dev unzip openssl libssl-dev pkg-config libsqlite3-dev libonig-dev lsb-release'
	echo "Updating system APT repositories..."
	apt-get -qq update
	echo "Installing dependencies for compilation..."
	apt-get -qq install -y $SOFTWARE

	# In a minimal/freshly-debootstrapped chroot, dpkg trigger processing
	# (which normally re-runs ldconfig after installing shared libs) can be
	# deferred or skipped, leaving the dynamic linker's cache stale even
	# though e.g. libzip.so.5 is genuinely on disk. Refresh it explicitly so
	# binaries built against these libs (php, nginx, ...) can actually run.
	ldconfig

	# Installing Node.js 24.x repo
	apt="/etc/apt/sources.list.d"
	codename="$(lsb_release -s -c)"

	if [ -z $(which "node") ]; then
		curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
	fi

	echo "Installing Node.js..."
	apt-get -qq update > /dev/null
	apt-get -qq install -y nodejs

	# NodeSource's nodejs package bundles npm, but Debian/Ubuntu's own nodejs
	# package doesn't (used if the NodeSource repo above failed to register,
	# e.g. no network). Only fall back to the distro's separate npm package
	# when npm is actually missing — requesting it unconditionally alongside
	# nodejs in one apt-get call conflicts with NodeSource's bundled npm and
	# fails the whole install.
	if [ -z "$(which "npm")" ]; then
		apt-get -qq install -y npm
	fi

	if [ -z "$(which "node")" ] || [ -z "$(which "npm")" ]; then
		echo "Failed to install Node.js/npm"
		exit 1
	fi

	nodejs_version=$(/usr/bin/node -v | cut -f1 -d'.' | sed 's/v//g')

	if [ "$nodejs_version" -lt 18 ]; then
		echo "Requires Node.js 18.x or higher"
		exit 1
	fi

	# Fix for Debian PHP environment
	if [ $BUILD_ARCH == "amd64" ]; then
		if [ ! -L /usr/local/include/curl ]; then
			ln -s /usr/include/x86_64-linux-gnu/curl /usr/local/include/curl
		fi
	fi
fi

# Get system cpu cores. Callers running this inside a QEMU-emulated chroot
# (cross-arch builds) can pre-set NUM_CPUS to override this: /proc is
# bind-mounted from the host, so the detected count would otherwise be the
# host's real core count, not a safe parallelism level for emulated compiles.
NUM_CPUS="${NUM_CPUS:-$(grep "^cpu cores" /proc/cpuinfo | uniq | awk '{print $4}')}"

if [ "$TULIO_DEBUG" ]; then
	echo "OS type          : Debian / Ubuntu"
	echo "Branch           : $branch"
	echo "Install          : $install"
	echo "Tulio version   : $BUILD_VER"
	echo "Nginx version    : $NGINX_V"
	echo "PHP version      : $PHP_V"
	echo "Web Term version : $WEB_TERMINAL_V"
	echo "Architecture     : $BUILD_ARCH"
	echo "Debug mode       : $TULIO_DEBUG"
	echo "Source directory : $SRC_DIR"
	echo "Build release    : $BUILD_RELEASE"
fi

# Generate Links for sourcecode
# TODO(tulio): infrastructure not yet deployed
TULIO_ARCHIVE_LINK='https://github.com/marcosfermin/tuliocp/archive/'$branch'.tar.gz'
if [[ $NGINX_V =~ - ]]; then
	NGINX='https://nginx.org/download/nginx-'$(echo $NGINX_V | cut -d"-" -f1)'.tar.gz'
else
	NGINX='https://nginx.org/download/nginx-'$(echo $NGINX_V | cut -d"~" -f1)'.tar.gz'
fi

OPENSSL='https://github.com/openssl/openssl/releases/download/openssl-'$OPENSSL_V'/openssl-'$OPENSSL_V'.tar.gz'
PCRE='https://github.com/PCRE2Project/pcre2/releases/download/pcre2-'$PCRE_V'/pcre2-'$PCRE_V'.tar.gz'
ZLIB='https://github.com/madler/zlib/archive/refs/tags/v'$ZLIB_V'.tar.gz'

if [[ $PHP_V =~ - ]]; then
	PHP='http://de2.php.net/distributions/php-'$(echo $PHP_V | cut -d"-" -f1)'.tar.gz'
else
	PHP='http://de2.php.net/distributions/php-'$(echo $PHP_V | cut -d"~" -f1)'.tar.gz'
fi

# Forward slashes in branchname are replaced with dashes to match foldername in github archive.
branch_dash=$(echo "$branch" | sed 's/\//-/g')

#################################################################################
#
# Building tulio-nginx
#
#################################################################################

if [ "$NGINX_B" = true ]; then

	echo "Building tulio-nginx package..."
	if [ "$CROSS" = "true" ]; then
		echo "Cross compile not supported for tulio-nginx, tulio-php or tulio-web-terminal"
		exit 1
	fi
	# Change to build directory
	cd $BUILD_DIR

	BUILD_DIR_TULIONGINX=$BUILD_DIR/tulio-nginx_$NGINX_V
	if [[ $NGINX_V =~ - ]]; then
		BUILD_DIR_NGINX=$BUILD_DIR/nginx-$(echo $NGINX_V | cut -d"-" -f1)
	else
		BUILD_DIR_NGINX=$BUILD_DIR/nginx-$(echo $NGINX_V | cut -d"~" -f1)
	fi

	if [ "$KEEPBUILD" != 'true' ] || [ ! -d "$BUILD_DIR_TULIONGINX" ] || [ ! -f "$BUILD_DIR_NGINX/Makefile" ]; then
		# Check if target directory exist
		if [ -d "$BUILD_DIR_TULIONGINX" ]; then
			#mv $BUILD_DIR/tulio-nginx_$NGINX_V $BUILD_DIR/tulio-nginx_$NGINX_V-$(timestamp)
			rm -r "$BUILD_DIR_TULIONGINX"
		fi

		# Create directory
		mkdir -p $BUILD_DIR_TULIONGINX

		# Download and unpack source files
		download_file $NGINX '-' | tar xz
		download_file $OPENSSL '-' | tar xz
		download_file $PCRE '-' | tar xz
		download_file $ZLIB '-' | tar xz

		# Change to nginx directory
		cd $BUILD_DIR_NGINX

		# configure nginx
		./configure --prefix=/usr/local/tulio/nginx \
			--with-http_v2_module \
			--with-http_ssl_module \
			--with-openssl=../openssl-$OPENSSL_V \
			--with-openssl-opt=enable-ec_nistp_64_gcc_128 \
			--with-openssl-opt=no-nextprotoneg \
			--with-openssl-opt=no-weak-ssl-ciphers \
			--with-openssl-opt=no-ssl3 \
			--with-pcre=../pcre2-$PCRE_V \
			--with-pcre-jit \
			--with-zlib=../zlib-$ZLIB_V
	fi

	# Change to nginx directory
	cd $BUILD_DIR_NGINX

	# Check install directory and remove if exists
	if [ -d "$BUILD_DIR$INSTALL_DIR" ]; then
		rm -r "$BUILD_DIR$INSTALL_DIR"
	fi

	# Copy local tulio source files
	if [ "$use_src_folder" == 'true' ] && [ -d $SRC_DIR ]; then
		cp -rf "$SRC_DIR/" $BUILD_DIR/tuliocp-$branch_dash
	fi

	# Create the files and install them
	make -j $NUM_CPUS && make DESTDIR=$BUILD_DIR install

	# Clear up unused files
	if [ "$KEEPBUILD" != 'true' ]; then
		rm -r $BUILD_DIR_NGINX $BUILD_DIR/openssl-$OPENSSL_V $BUILD_DIR/pcre2-$PCRE_V $BUILD_DIR/zlib-$ZLIB_V
	fi
	cd $BUILD_DIR_TULIONGINX

	# Move nginx directory
	mkdir -p $BUILD_DIR_TULIONGINX/usr/local/tulio
	rm -rf $BUILD_DIR_TULIONGINX/usr/local/tulio/nginx
	mv $BUILD_DIR/usr/local/tulio/nginx $BUILD_DIR_TULIONGINX/usr/local/tulio/

	# Remove original nginx.conf (will use custom)
	rm -f $BUILD_DIR_TULIONGINX/usr/local/tulio/nginx/conf/nginx.conf

	# copy binary
	mv $BUILD_DIR_TULIONGINX/usr/local/tulio/nginx/sbin/nginx $BUILD_DIR_TULIONGINX/usr/local/tulio/nginx/sbin/tulio-nginx

	# change permission and build the package
	cd $BUILD_DIR
	chown -R root:root $BUILD_DIR_TULIONGINX
	# Get Debian package files
	mkdir -p $BUILD_DIR_TULIONGINX/DEBIAN
	get_branch_file 'src/deb/nginx/control' "$BUILD_DIR_TULIONGINX/DEBIAN/control"
	if [ "$BUILD_ARCH" != "amd64" ]; then
		sed -i "s/amd64/${BUILD_ARCH}/g" "$BUILD_DIR_TULIONGINX/DEBIAN/control"
	fi
	apply_distro_version "$BUILD_DIR_TULIONGINX/DEBIAN/control"
	get_branch_file 'src/deb/nginx/copyright' "$BUILD_DIR_TULIONGINX/DEBIAN/copyright"
	get_branch_file 'src/deb/nginx/postinst' "$BUILD_DIR_TULIONGINX/DEBIAN/postinst"
	get_branch_file 'src/deb/nginx/postrm' "$BUILD_DIR_TULIONGINX/DEBIAN/portrm"
	chmod +x "$BUILD_DIR_TULIONGINX/DEBIAN/postinst"
	chmod +x "$BUILD_DIR_TULIONGINX/DEBIAN/portrm"

	# Init file
	mkdir -p $BUILD_DIR_TULIONGINX/etc/init.d
	get_branch_file 'src/deb/nginx/tulio' "$BUILD_DIR_TULIONGINX/etc/init.d/tulio"
	chmod +x "$BUILD_DIR_TULIONGINX/etc/init.d/tulio"

	# Custom config
	get_branch_file 'src/deb/nginx/nginx.conf' "${BUILD_DIR_TULIONGINX}/usr/local/tulio/nginx/conf/nginx.conf"

	# Build the package
	echo Building Nginx DEB
	dpkg-deb -Zxz --build $BUILD_DIR_TULIONGINX $DEB_DIR

	rm -r $BUILD_DIR/usr

	if [ "$KEEPBUILD" != 'true' ]; then
		# Clean up the source folder
		rm -r tulio- nginx_$NGINX_V
		rm -rf $BUILD_DIR/rpmbuild
		if [ "$use_src_folder" == 'true' ] && [ -d $BUILD_DIR/tuliocp-$branch_dash ]; then
			rm -r $BUILD_DIR/tuliocp-$branch_dash
		fi
	fi
fi

#################################################################################
#
# Building tulio-php
#
#################################################################################

if [ "$PHP_B" = true ]; then
	echo "Building tulio-php package..."
	if [ "$CROSS" = "true" ]; then
		echo "Cross compile not supported for tulio-nginx, tulio-php or tulio-web-terminal"
		exit 1
	fi

	BUILD_DIR_TULIOPHP=$BUILD_DIR/tulio-php_$PHP_V

	BUILD_DIR_PHP=$BUILD_DIR/php-$(echo $PHP_V | cut -d"~" -f1)

	if [[ $PHP_V =~ - ]]; then
		BUILD_DIR_PHP=$BUILD_DIR/php-$(echo $PHP_V | cut -d"-" -f1)
	else
		BUILD_DIR_PHP=$BUILD_DIR/php-$(echo $PHP_V | cut -d"~" -f1)
	fi

	if [ "$KEEPBUILD" != 'true' ] || [ ! -d "$BUILD_DIR_TULIOPHP" ] || [ ! -f "$BUILD_DIR_PHP/Makefile" ]; then
		# Check if target directory exist
		if [ -d $BUILD_DIR_TULIOPHP ]; then
			rm -r $BUILD_DIR_TULIOPHP
		fi

		# Create directory
		mkdir -p $BUILD_DIR_TULIOPHP

		# Download and unpack source files
		cd $BUILD_DIR
		download_file $PHP '-' | tar xz

		# Change to untarred php directory
		cd $BUILD_DIR_PHP

		# Configure PHP
		./configure --prefix=/usr/local/tulio/php \
			--with-libdir=lib/$(arch)-linux-gnu \
			--enable-fpm --with-fpm-user=admin --with-fpm-group=admin \
			--with-openssl \
			--with-mysqli \
			--with-gettext \
			--with-curl \
			--with-zip \
			--with-gmp \
			--enable-mbstring
	fi

	cd $BUILD_DIR_PHP

	# Create the files and install them
	make -j $NUM_CPUS && make INSTALL_ROOT=$BUILD_DIR install

	# Copy local tulio source files
	if [ "$use_src_folder" == 'true' ] && [ -d $SRC_DIR ]; then
		[ "$TULIO_DEBUG" ] && echo DEBUG: cp -rf "$SRC_DIR/" $BUILD_DIR/tuliocp-$branch_dash
		cp -rf "$SRC_DIR/" $BUILD_DIR/tuliocp-$branch_dash
	fi
	# Move php directory
	[ "$TULIO_DEBUG" ] && echo DEBUG: mkdir -p $BUILD_DIR_TULIOPHP/usr/local/tulio
	mkdir -p $BUILD_DIR_TULIOPHP/usr/local/tulio

	[ "$TULIO_DEBUG" ] && echo DEBUG: rm -r $BUILD_DIR_TULIOPHP/usr/local/tulio/php
	if [ -d $BUILD_DIR_TULIOPHP/usr/local/tulio/php ]; then
		rm -r $BUILD_DIR_TULIOPHP/usr/local/tulio/php
	fi

	[ "$TULIO_DEBUG" ] && echo DEBUG: mv ${BUILD_DIR}/usr/local/tulio/php ${BUILD_DIR_TULIOPHP}/usr/local/tulio/
	mv ${BUILD_DIR}/usr/local/tulio/php ${BUILD_DIR_TULIOPHP}/usr/local/tulio/

	# copy binary
	[ "$TULIO_DEBUG" ] && echo DEBUG: cp $BUILD_DIR_TULIOPHP/usr/local/tulio/php/sbin/php-fpm $BUILD_DIR_TULIOPHP/usr/local/tulio/php/sbin/tulio-php
	cp $BUILD_DIR_TULIOPHP/usr/local/tulio/php/sbin/php-fpm $BUILD_DIR_TULIOPHP/usr/local/tulio/php/sbin/tulio-php

	# Change permissions and build the package
	chown -R root:root $BUILD_DIR_TULIOPHP
	# Get Debian package files
	[ "$TULIO_DEBUG" ] && echo DEBUG: mkdir -p $BUILD_DIR_TULIOPHP/DEBIAN
	mkdir -p $BUILD_DIR_TULIOPHP/DEBIAN
	get_branch_file 'src/deb/php/control' "$BUILD_DIR_TULIOPHP/DEBIAN/control"
	if [ "$BUILD_ARCH" != "amd64" ]; then
		sed -i "s/amd64/${BUILD_ARCH}/g" "$BUILD_DIR_TULIOPHP/DEBIAN/control"
	fi
	apply_distro_version "$BUILD_DIR_TULIOPHP/DEBIAN/control"

	# Extract correct libs as depends
	PHP_BIN="$BUILD_DIR_TULIOPHP/usr/local/tulio/php/sbin/tulio-php"
	LIBZIP_DEP=$(detect_pkg_from_elf "$PHP_BIN" "libzip")
	ONIG_DEP=$(detect_pkg_from_elf "$PHP_BIN" "libonig")
	sed -i \
		-e "s/@LIBZIP_DEP@/${LIBZIP_DEP}/g" \
		-e "s/@ONIG_DEP@/${ONIG_DEP}/g" \
		"$BUILD_DIR_TULIOPHP/DEBIAN/control"

	get_branch_file 'src/deb/php/copyright' "$BUILD_DIR_TULIOPHP/DEBIAN/copyright"
	get_branch_file 'src/deb/php/postinst' "$BUILD_DIR_TULIOPHP/DEBIAN/postinst"
	chmod +x $BUILD_DIR_TULIOPHP/DEBIAN/postinst
	# Get custom config
	get_branch_file 'src/deb/php/php-fpm.conf' "${BUILD_DIR_TULIOPHP}/usr/local/tulio/php/etc/php-fpm.conf"
	get_branch_file 'src/deb/php/php.ini' "${BUILD_DIR_TULIOPHP}/usr/local/tulio/php/lib/php.ini"

	# Build the package
	echo Building PHP DEB
	[ "$TULIO_DEBUG" ] && echo DEBUG: dpkg-deb -Zxz --build $BUILD_DIR_TULIOPHP $DEB_DIR
	dpkg-deb -Zxz --build $BUILD_DIR_TULIOPHP $DEB_DIR

	rm -r $BUILD_DIR/usr

	# clear up the source folder
	if [ "$KEEPBUILD" != 'true' ]; then
		rm -r $BUILD_DIR/php-$(echo $PHP_V | cut -d"~" -f1)
		rm -r $BUILD_DIR_TULIOPHP
		if [ "$use_src_folder" == 'true' ] && [ -d $BUILD_DIR/tuliocp-$branch_dash ]; then
			rm -r $BUILD_DIR/tuliocp-$branch_dash
		fi
	fi
fi

#################################################################################
#
# Building tulio-web-terminal
#
#################################################################################

if [ "$WEB_TERMINAL_B" = true ]; then
	echo "Building tulio-web-terminal package..."
	if [ "$CROSS" = "true" ]; then
		echo "Cross compile not supported for tulio-nginx, tulio-php or tulio-web-terminal"
		exit 1
	fi

	BUILD_DIR_TULIO_TERMINAL=$BUILD_DIR/tulio-web-terminal_$WEB_TERMINAL_V

	# Check if target directory exist
	if [ -d $BUILD_DIR_TULIO_TERMINAL ]; then
		rm -r $BUILD_DIR_TULIO_TERMINAL
	fi

	# Create directory
	mkdir -p $BUILD_DIR_TULIO_TERMINAL
	chown -R root:root $BUILD_DIR_TULIO_TERMINAL

	# Get Debian package files
	[ "$TULIO_DEBUG" ] && echo DEBUG: mkdir -p $BUILD_DIR_TULIO_TERMINAL/DEBIAN
	mkdir -p $BUILD_DIR_TULIO_TERMINAL/DEBIAN
	get_branch_file 'src/deb/web-terminal/control' "$BUILD_DIR_TULIO_TERMINAL/DEBIAN/control"
	if [ "$BUILD_ARCH" != "amd64" ]; then
		sed -i "s/amd64/${BUILD_ARCH}/g" "$BUILD_DIR_TULIO_TERMINAL/DEBIAN/control"
	fi
	apply_distro_version "$BUILD_DIR_TULIO_TERMINAL/DEBIAN/control"
	get_branch_file 'src/deb/web-terminal/copyright' "$BUILD_DIR_TULIO_TERMINAL/DEBIAN/copyright"
	get_branch_file 'src/deb/web-terminal/postinst' "$BUILD_DIR_TULIO_TERMINAL/DEBIAN/postinst"
	chmod +x $BUILD_DIR_TULIO_TERMINAL/DEBIAN/postinst

	# Get server files
	[ "$TULIO_DEBUG" ] && echo DEBUG: mkdir -p "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal"
	mkdir -p "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal"
	get_branch_file 'src/deb/web-terminal/package.json' "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/package.json"
	get_branch_file 'src/deb/web-terminal/package-lock.json' "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/package-lock.json"
	get_branch_file 'src/deb/web-terminal/server.js' "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/server.js"
	get_branch_file 'src/deb/web-terminal/web-terminal-session-auth.php' "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/web-terminal-session-auth.php"
	chmod +x "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/server.js"
	chmod +x "${BUILD_DIR_TULIO_TERMINAL}/usr/local/tulio/web-terminal/web-terminal-session-auth.php"

	cd $BUILD_DIR_TULIO_TERMINAL/usr/local/tulio/web-terminal
	npm ci --omit=dev

	# Systemd service
	[ "$TULIO_DEBUG" ] && echo DEBUG: mkdir -p $BUILD_DIR_TULIO_TERMINAL/etc/systemd/system
	mkdir -p $BUILD_DIR_TULIO_TERMINAL/etc/systemd/system
	get_branch_file 'src/deb/web-terminal/tulio-web-terminal.service' "$BUILD_DIR_TULIO_TERMINAL/etc/systemd/system/tulio-web-terminal.service"

	# Build the package
	echo Building Web Terminal DEB
	[ "$TULIO_DEBUG" ] && echo DEBUG: dpkg-deb -Zxz --build $BUILD_DIR_TULIO_TERMINAL $DEB_DIR
	dpkg-deb -Zxz --build $BUILD_DIR_TULIO_TERMINAL $DEB_DIR

	# clear up the source folder
	if [ "$KEEPBUILD" != 'true' ]; then
		rm -r $BUILD_DIR_TULIO_TERMINAL
		if [ "$use_src_folder" == 'true' ] && [ -d $BUILD_DIR/tuliocp-$branch_dash ]; then
			rm -r $BUILD_DIR/tuliocp-$branch_dash
		fi
	fi
fi

#################################################################################
#
# Building tulio
#
#################################################################################

arch="$BUILD_ARCH"

if [ "$TULIO_B" = true ]; then
	if [ "$CROSS" = "true" ]; then
		arch="amd64 arm64"
	else
		arch="$BUILD_ARCH"
		supported_os=$(get_distro_suffix)
	fi

	echo "Building Tulio Control Panel package..."

	BUILD_DIR_TULIO=$BUILD_DIR/tulio_$TULIO_V

	# Change to build directory
	cd $BUILD_DIR

	if [ "$KEEPBUILD" != 'true' ] || [ ! -d "$BUILD_DIR_TULIO" ]; then
		# Check if target directory exist
		if [ -d $BUILD_DIR_TULIO ]; then
			rm -r $BUILD_DIR_TULIO
		fi

		# Create directory
		mkdir -p $BUILD_DIR_TULIO
	fi

	cd $BUILD_DIR
	rm -rf $BUILD_DIR/tuliocp-$branch_dash
	# Download and unpack source files
	if [ "$use_src_folder" == 'true' ]; then
		[ "$TULIO_DEBUG" ] && echo DEBUG: cp -rf "$SRC_DIR/" $BUILD_DIR/tuliocp-$branch_dash
		cp -rf "$SRC_DIR/" $BUILD_DIR/tuliocp-$branch_dash
	elif [ -d $SRC_DIR ]; then
		download_file $TULIO_ARCHIVE_LINK '-' 'fresh' | tar xz
	fi

	mkdir -p $BUILD_DIR_TULIO/usr/local/tulio

	# Build web and move needed directories
	cd $BUILD_DIR/tuliocp-$branch_dash
	npm ci --ignore-scripts
	npm run build
	for BUILD_ARCH in $arch; do
		for os in $supported_os; do
			mkdir -p $BUILD_DIR_TULIO/usr/local/tulio
			cp -rf bin func install web $BUILD_DIR_TULIO/usr/local/tulio/

			# Set permissions
			find $BUILD_DIR_TULIO/usr/local/tulio/ -type f -exec chmod -x {} \;

			# Allow send email via /usr/local/tulio/web/inc/mail-wrapper.php via cli
			chmod +x $BUILD_DIR_TULIO/usr/local/tulio/web/inc/mail-wrapper.php
			# Allow the executable to be executed
			chmod +x $BUILD_DIR_TULIO/usr/local/tulio/bin/*
			find $BUILD_DIR_TULIO/usr/local/tulio/install/ \( -name '*.sh' \) -exec chmod +x {} \;
			chmod -x $BUILD_DIR_TULIO/usr/local/tulio/install/*.sh
			chown -R root:root $BUILD_DIR_TULIO
			# Get Debian package files
			mkdir -p $BUILD_DIR_TULIO/DEBIAN
			get_branch_file 'src/deb/tulio/control' "$BUILD_DIR_TULIO/DEBIAN/control"
			if [ "$BUILD_ARCH" != "amd64" ]; then
				sed -i "s/amd64/${BUILD_ARCH}/g" "$BUILD_DIR_TULIO/DEBIAN/control"
			fi
			apply_distro_version "$BUILD_DIR_TULIO/DEBIAN/control" "$os"
			get_branch_file 'src/deb/tulio/copyright' "$BUILD_DIR_TULIO/DEBIAN/copyright"
			get_branch_file 'src/deb/tulio/preinst' "$BUILD_DIR_TULIO/DEBIAN/preinst"
			get_branch_file 'src/deb/tulio/postinst' "$BUILD_DIR_TULIO/DEBIAN/postinst"
			chmod +x $BUILD_DIR_TULIO/DEBIAN/postinst
			chmod +x $BUILD_DIR_TULIO/DEBIAN/preinst

			echo Building Tulio DEB
			dpkg-deb -Zxz --build $BUILD_DIR_TULIO $DEB_DIR

			# clear up the source folder
			if [ "$KEEPBUILD" != 'true' ]; then
				rm -r $BUILD_DIR_TULIO
				rm -rf tuliocp-$branch_dash
			fi
			cd $BUILD_DIR/tuliocp-$branch_dash
		done
	done
fi

#################################################################################
#
# Install Packages
#
#################################################################################

if [ "$install" = 'yes' ] || [ "$install" = 'y' ] || [ "$install" = 'true' ]; then
	# Install all available packages
	echo "Installing packages..."
	for i in $DEB_DIR/*.deb; do
		dpkg -i $i
		if [ $? -ne 0 ]; then
			exit 1
		fi
	done
	unset $answer
fi
