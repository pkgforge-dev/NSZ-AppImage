#!/bin/sh

set -ex

ARCH="$(uname -m)"
URUNTIME="https://github.com/VHSgunzo/uruntime/releases/latest/download/uruntime-appimage-dwarfs-$ARCH"
URUNTIME_LITE="https://github.com/VHSgunzo/uruntime/releases/latest/download/uruntime-appimage-dwarfs-lite-$ARCH"
SHARUN="https://github.com/VHSgunzo/sharun/releases/latest/download/sharun-$ARCH-aio"
UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*$ARCH.AppImage.zsync"

# github actions doesn't set USER
export USER=USER

# Prepare AppDir
mkdir -p ./AppDir && (
	cd ./AppDir

	# ADD LIBRARIES
	wget --retry-connrefused --tries=30 "$SHARUN" -O ./sharun-aio
	chmod +x ./sharun-aio
	xvfb-run -a -- \
		./sharun-aio l        \
		--strip               \
		--with-hooks          \
		--python-ver 3.12     \
		--python-pkg nsz[gui] \
		--dst-dir ./ sharun -- nsz

	# barely anythign is dlopened because the app needs some file to start the gui
	# so we will add the rest of deps manually
	./sharun-aio l -v -s -k \
		/usr/lib/libdbus-*     \
		/usr/lib/libmtdev*     \
		/usr/lib/lib*GL*       \
		/usr/lib/dri/*         \
		/usr/lib/libudev*      \
		/usr/lib/libdrm*       \
		/usr/lib/libxcb-*      \
		/usr/lib/libXss*       \
		/usr/lib/libxcb-randr* \
		/usr/lib/libwayland*
	rm -f ./sharun-aio

	ln ./sharun ./AppRun
	./sharun -g

	# sharun is not stripping python due to issues with other packages
	# however that issue is not present here lol
	strip --strip-all ./lib/libpython*
	find ./lib/python* -type f -name '*.so*' -exec strip --strip-all {} \;

	echo "Adding icon and desktop entry..."
	# Does this project have an icon???
	touch ./.DirIcon
	touch ./nsz.png

	cat <<-'KEK' > ./nsz.desktop
	[Desktop Entry]
	Version=1.0
	Type=Application
	Name=NSZ[GUI]
	TryExec=nsz
	MimeType=application/x-nx-nro;application/x-nx-nso;application/x-nx-nsp;application/x-nx-xci;
	Exec=nsz %F
	Icon=nsz
	Categories=Utility;
	StartupWMClass=nsz
	KEK
)

VERSION="$(awk '/^Version:/{printf "%s", $2; exit}' \
	./AppDir/lib/python*/site-packages/nsz-*.dist-info/METADATA | tr -d '[:space:]'
)"
[ -n "$VERSION" ] && echo "$VERSION" > ~/version

# MAKE APPIMAGE WITH URUNTIME
wget --retry-connrefused --tries=30 "$URUNTIME"      -O  ./uruntime
wget --retry-connrefused --tries=30 "$URUNTIME_LITE" -O  ./uruntime-lite
chmod +x ./uruntime*

# Add udpate info to runtime
echo "Adding update information \"$UPINFO\" to runtime..."
./uruntime-lite --appimage-addupdinfo "$UPINFO"

echo "Generating AppImage..."
./uruntime \
	--appimage-mkdwarfs -f               \
	--set-owner 0 --set-group 0          \
	--no-history --no-create-timestamp   \
	--compression zstd:level=22 -S26 -B8 \
	--header uruntime-lite               \
	-i ./AppDir                          \
	-o ./NSZ-"$VERSION"-anylinux-"$ARCH".AppImage

# make appbundle
UPINFO="$(echo "$UPINFO" | sed 's#.AppImage.zsync#*.AppBundle.zsync#g')"
wget --retry-connrefused --tries=30 \
	"https://github.com/xplshn/pelf/releases/latest/download/pelf_$ARCH" -O ./pelf
chmod +x ./pelf
echo "Generating [dwfs]AppBundle..."
./pelf \
	--compression "-C zstd:level=22 -S26 -B8" \
	--appbundle-id="NSZ-$VERSION"             \
	--appimage-compat                         \
	--add-updinfo "$UPINFO"                   \
	--add-appdir ./AppDir                     \
	--output-to ./NSZ-"$VERSION"-anylinux-"$ARCH".dwfs.AppBundle

zsyncmake ./*.AppImage -u ./*.AppImage
zsyncmake ./*.AppBundle -u ./*.AppBundle

mkdir -p ./dist
mv -v ./*.AppImage*  ./dist
mv -v ./*.AppBundle* ./dist

echo "All Done!"
