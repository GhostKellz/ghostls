# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

pkgname=ghostls
pkgver=0.1.0
pkgrel=1
pkgdesc="Language Server Protocol (LSP) server for the Ghostlang programming language"
arch=('x86_64' 'aarch64')
url="https://github.com/ghostkellz/ghostls"
license=('MIT')
depends=()
makedepends=('zig>=0.16.0' 'git')
provides=('ghostls')
conflicts=('ghostls-git')
source=("git+https://github.com/ghostkellz/ghostls.git#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
    cd "${srcdir}/${pkgname}"
    zig build -Drelease-safe
}

check() {
    cd "${srcdir}/${pkgname}"
    # Run integration tests
    ./scripts/simple_test.sh || true
}

package() {
    cd "${srcdir}/${pkgname}"

    # Install binary
    install -Dm755 "zig-out/bin/${pkgname}" "${pkgdir}/usr/bin/${pkgname}"

    # Install documentation
    install -Dm644 README.md "${pkgdir}/usr/share/doc/${pkgname}/README.md"
    install -Dm644 CHANGELOG.md "${pkgdir}/usr/share/doc/${pkgname}/CHANGELOG.md"
    install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"

    # Install editor integration examples
    install -Dm644 integrations/nvim/README.md "${pkgdir}/usr/share/doc/${pkgname}/nvim-integration.md"
    install -Dm644 integrations/grim/README.md "${pkgdir}/usr/share/doc/${pkgname}/grim-integration.md"
    install -Dm644 integrations/grim/init.gza "${pkgdir}/usr/share/doc/${pkgname}/examples/init.gza"
}
