# Maintainer: Sebastien MacDougall-Landry

pkgname=mpv-jellyfin
pkgver=1.1
pkgrel=1
pkgdesc='mpv plugin that turns it into a Jellyfin client'
url='https://github.com/EmperorPenguin18/mpv-jellyfin/'
source=("$pkgname-$pkgver.tar.gz::https://github.com/EmperorPenguin18/mpv-jellyfin/archive/refs/tags/$pkgver.tar.gz")
arch=('any')
license=('Unlicense')
depends=('mpv' 'curl')
sha256sums=('')

package () {
  cd "$srcdir/$pkgname-$pkgver"
  install -Dm644 scripts/jellyfin.lua -t "$pkgdir/etc/mpv/scripts"
  install -Dm644 script-opts/jellyfin.conf -t "$pkgdir/etc/mpv/script-opts"
}
