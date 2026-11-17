#!/usr/bin/env bash
# Linux用の .deb パッケージを作る。
#   bash packaging/linux/build-deb.sh            # amd64 (x64)
#   bash packaging/linux/build-deb.sh arm64      # arm64
# 出力: dist/shibajintori_<version>_<arch>.deb
#
# インストール先:
#   /opt/ShibaJintori/                    ゲーム本体 (.NETランタイムとSDL3を同梱)
#   /usr/bin/shibajintori                 起動用スクリプト
#   /usr/share/applications/shibajintori.desktop
#   /usr/share/icons/hicolor/<size>/apps/shibajintori.png
set -euo pipefail

ARCH="${1:-amd64}"
case "$ARCH" in
  amd64) RID=linux-x64 ;;
  arm64) RID=linux-arm64 ;;
  *) echo "unknown architecture: $ARCH (amd64 or arm64)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' ShibaJintori.csproj | head -n 1)"
VERSION="${VERSION:-1.0.1}"
MAINTAINER="${MAINTAINER:-Shiba Jintori Developers <shibajintori@localhost>}"
echo "== Shiba Jintori $VERSION ($ARCH) =="

command -v dpkg-deb >/dev/null || { echo "dpkg-deb が見つかりません (sudo apt install dpkg-dev)" >&2; exit 1; }

PUBLISH="$ROOT/dist/$RID"
rm -rf "$PUBLISH"
dotnet publish ShibaJintori.csproj -c Release -r "$RID" --self-contained true -p:DebugType=none -o "$PUBLISH"

# パッケージの中身は /tmp に組み立てる (WSLでWindows側のフォルダだとパーミッションを設定できないため)
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/shibajintori_${VERSION}_${ARCH}"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/ShibaJintori" "$PKG/usr/bin" "$PKG/usr/share/applications"

cp -r "$PUBLISH/." "$PKG/opt/ShibaJintori/"
cp packaging/linux/shibajintori.desktop "$PKG/usr/share/applications/shibajintori.desktop"
for size in 16 24 32 48 64 128 256; do
  dir="$PKG/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "packaging/icons/shibajintori-${size}.png" "$dir/shibajintori.png"
done

cat > "$PKG/usr/bin/shibajintori" <<'EOS'
#!/bin/sh
exec /opt/ShibaJintori/ShibaJintori "$@"
EOS

find "$PKG" -type d -exec chmod 755 {} +
find "$PKG" -type f -exec chmod 644 {} +
chmod 755 "$PKG/opt/ShibaJintori/ShibaJintori" "$PKG/usr/bin/shibajintori"
[ -f "$PKG/opt/ShibaJintori/createdump" ] && chmod 755 "$PKG/opt/ShibaJintori/createdump"

SIZE_KB="$(du -sk "$PKG/opt" "$PKG/usr" | awk '{s += $1} END {print s}')"
cat > "$PKG/DEBIAN/control" <<EOS
Package: shibajintori
Version: $VERSION
Section: games
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $SIZE_KB
Depends: libc6, libstdc++6, libgcc-s1
Description: Shiba Jintori - a territory action game starring a Shiba Inu
 Walk your Shiba Inu around the field, mark three utility poles and claim
 the triangle between them as your territory before the other dogs do.
EOS

cat > "$PKG/DEBIAN/postinst" <<'EOS'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q /usr/share/applications || true; fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true; fi
EOS
cp "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

OUT="$ROOT/dist/shibajintori_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG" "$OUT"
echo "Done: $OUT"
echo "インストール: sudo apt install \"$OUT\""
