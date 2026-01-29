#!/usr/bin/env bash
set -euo pipefail

# Shared source-build helper for sysroots.
# Supported libs: openssl

SRC_BUILD_MODE="${SRC_BUILD_MODE:-}"
SYSROOT_DIR="${SYSROOT_DIR:-}"
SRC_BUILDS="${SRC_BUILDS:-openssl}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.2}"
OPENSSL_URL="${OPENSSL_URL:-https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz}"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-/usr}"
OPENSSL_DIR="${OPENSSL_DIR:-/etc/ssl}"
OPENSSL_LIBDIR="${OPENSSL_LIBDIR:-lib64}"
SUDO="${SUDO:-}"

if [ -z "$SYSROOT_DIR" ]; then
    echo "ERROR: SYSROOT_DIR is required."
    exit 1
fi

if [[ "$SRC_BUILDS" != *"openssl"* ]]; then
    echo "No source builds requested (SRC_BUILDS=$SRC_BUILDS)."
    exit 0
fi

if [ -z "$SRC_BUILD_MODE" ]; then
    echo "ERROR: SRC_BUILD_MODE is required (debian|ocs|native)."
    exit 1
fi

enable_openssl_legacy_provider() {
    local conf=""
    if [ -f "$SYSROOT_DIR/etc/ssl/openssl.cnf" ]; then
        conf="$SYSROOT_DIR/etc/ssl/openssl.cnf"
    elif [ -f "$SYSROOT_DIR/etc/pki/tls/openssl.cnf" ]; then
        conf="$SYSROOT_DIR/etc/pki/tls/openssl.cnf"
    else
        echo "WARNING: openssl.cnf not found; skipping legacy provider enable."
        return 0
    fi

    python3 - "$conf" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

if not re.search(r"^\s*openssl_conf\s*=", data, re.M):
    data = "openssl_conf = openssl_init\n\n" + data

if "openssl_init" not in data:
    data += "\n\n[openssl_init]\n"
    data += "providers = provider_sect\n\n"

if "provider_sect" not in data:
    data += "[provider_sect]\n"
    data += "default = default_sect\n"
    data += "legacy = legacy_sect\n\n"

if "legacy_sect" not in data:
    data += "[legacy_sect]\n"
    data += "activate = 1\n\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(data)
PY

    echo "✅ Enabled OpenSSL legacy provider in $conf"
}

verify_openssl_symbols() {
    local libcrypto libssl
    libcrypto="$(find "$SYSROOT_DIR/usr/lib64" "$SYSROOT_DIR/lib64" "$SYSROOT_DIR/usr/lib" "$SYSROOT_DIR/lib" -name 'libcrypto.so.3' 2>/dev/null | head -n 1)"
    libssl="$(find "$SYSROOT_DIR/usr/lib64" "$SYSROOT_DIR/lib64" "$SYSROOT_DIR/usr/lib" "$SYSROOT_DIR/lib" -name 'libssl.so.3' 2>/dev/null | head -n 1)"

    if [ -z "$libcrypto" ] || [ -z "$libssl" ]; then
        echo "❌ CRITICAL: OpenSSL libs not found for symbol verification."
        echo "libcrypto: ${libcrypto:-<missing>}"
        echo "libssl: ${libssl:-<missing>}"
        return 1
    fi

    local crypto_syms=(
        EVP_PKEY_get_bn_param
        EVP_PKEY_get_utf8_string_param
        EVP_PKEY_get_security_bits
        EVP_PKEY_get_id
        EVP_PKEY_get0_type_name
        EVP_PKEY_get_group_name
        EVP_PKEY_generate
        EVP_PKEY_fromdata_init
        EVP_PKEY_fromdata
        EVP_PKEY_todata
        EVP_PKEY_eq
        EVP_PKEY_CTX_new_from_name
        EVP_PKEY_CTX_new_from_pkey
        EVP_PKEY_CTX_set_params
        EVP_PKEY_Q_keygen
        EVP_KDF_fetch
        EVP_KDF_derive
        EVP_KDF_CTX_new
        EVP_KDF_CTX_free
        EVP_KDF_free
        OSSL_LIB_CTX_new
        OSSL_LIB_CTX_free
        OSSL_LIB_CTX_load_config
        OSSL_PROVIDER_load
        OSSL_PROVIDER_unload
        OSSL_PROVIDER_available
        OSSL_PARAM_construct_end
        OSSL_PARAM_construct_int
        OSSL_PARAM_construct_uint
        OSSL_PARAM_construct_octet_string
        OSSL_PARAM_construct_utf8_string
        OSSL_PARAM_get_BN
        OSSL_PARAM_get_octet_string_ptr
        OSSL_PARAM_locate
        OSSL_PARAM_locate_const
        OSSL_PARAM_merge
        OSSL_PARAM_free
        OSSL_PARAM_BLD_new
        OSSL_PARAM_BLD_free
        OSSL_PARAM_BLD_push_BN
        OSSL_PARAM_BLD_push_utf8_string
        OSSL_PARAM_BLD_push_octet_string
        OSSL_PARAM_BLD_to_param
        OSSL_STORE_open
        OSSL_STORE_open_ex
        OSSL_STORE_load
        OSSL_STORE_close
        OSSL_STORE_expect
        OSSL_STORE_INFO_get_type
        OSSL_STORE_INFO_get1_CERT
        OSSL_STORE_INFO_get1_PKEY
        OSSL_STORE_INFO_get1_PUBKEY
        OSSL_STORE_INFO_free
        EVP_CipherInit_ex2
        EVP_CIPHER_fetch
        EVP_CIPHER_free
        EVP_CIPHER_get_iv_length
        EVP_CIPHER_get_key_length
        EVP_CIPHER_CTX_get0_cipher
        EVP_CIPHER_CTX_get_iv_length
        EVP_CIPHER_CTX_get_key_length
        EVP_CIPHER_CTX_get_block_size
        EVP_aes_128_ocb
        EVP_aes_192_ocb
        EVP_aes_256_ocb
        EVP_sha512_256
        EVP_idea_cfb64
        EC_GROUP_new_by_curve_name_ex
        EC_POINT_oct2point
        EC_POINT_point2oct
        i2d_DSA_SIG
        DSA_SIG_new
        DSA_SIG_free
        DSA_SIG_set0
        i2d_ECDSA_SIG
        d2i_ECDSA_SIG
        X509_NAME_dup
        X509_LOOKUP_ctrl
        X509V3_add_standard_extensions
        X509_get_signature_nid
        X509_get0_signature
        X509_get0_extensions
        X509_ALGOR_get0
        X509_STORE_up_ref
        OCSP_cert_status_str
        OCSP_crl_reason_str
        OCSP_response_status_str
        ERR_get_error_all
        CRYPTO_clear_free
        BN_set_flags
        BIO_meth_set_gets
        PEM_read_bio_Parameters
        PEM_X509_INFO_read_bio
        UI_create_method
        UI_destroy_method
        UI_method_get_opener
        UI_method_get_reader
        UI_method_get_writer
        UI_method_get_closer
        UI_method_set_opener
        UI_method_set_reader
        UI_method_set_writer
        UI_method_set_closer
        UI_get_input_flags
        UI_get_string_type
        UI_set_result
    )

    local ssl_syms=(
        SSL_CTX_new_ex
        SSL_CTX_set0_tmp_dh_pkey
        SSL_CTX_up_ref
        SSL_CTX_set_info_callback
        SSL_CTX_set_default_read_buffer_len
        SSL_set_ciphersuites
        SSL_write_early_data
        SSL_SESSION_get_max_early_data
        SSL_get_early_data_status
        SSL_get_peer_signature_type_nid
        SSL_get0_group_name
    )

    local missing=0
    for sym in "${crypto_syms[@]}"; do
        if ! readelf -Ws "$libcrypto" | awk '{print $8}' | grep -qx "$sym"; then
            echo "❌ Missing libcrypto symbol: $sym"
            missing=1
        fi
    done
    for sym in "${ssl_syms[@]}"; do
        if ! readelf -Ws "$libssl" | awk '{print $8}' | grep -qx "$sym"; then
            echo "❌ Missing libssl symbol: $sym"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo "❌ OpenSSL symbol verification failed."
        return 1
    fi
    echo "✅ OpenSSL symbol verification passed."
}

build_openssl_native() {
    local fetcher=""
    if command -v curl >/dev/null 2>&1; then
        fetcher="curl"
    elif command -v wget >/dev/null 2>&1; then
        fetcher="wget"
    fi

    if command -v gcc >/dev/null 2>&1 && \
        command -v make >/dev/null 2>&1 && \
        command -v perl >/dev/null 2>&1 && \
        { [ -n "$fetcher" ]; } && \
        command -v tar >/dev/null 2>&1; then
        echo "✅ Build tools already available; skipping package install."
    else
    if command -v dnf >/dev/null 2>&1; then
        local dnf_bin
        dnf_bin="$(command -v dnf)"
        run_dnf() {
            if [ -n "$SUDO" ]; then
                $SUDO "$dnf_bin" "$@"
            else
                "$dnf_bin" "$@"
            fi
        }
        run_dnf -y install gcc make perl-core perl-IPC-Cmd ca-certificates tar curl-minimal || \
            run_dnf -y install gcc make perl ca-certificates tar curl-minimal || \
            run_dnf -y install gcc make perl-core perl-IPC-Cmd ca-certificates tar wget || \
            run_dnf -y install gcc make perl ca-certificates tar wget || \
            run_dnf --assumeyes install gcc make perl-core perl-IPC-Cmd ca-certificates tar curl-minimal || \
            run_dnf --assumeyes install gcc make perl ca-certificates tar curl-minimal || \
            run_dnf --assumeyes install gcc make perl-core perl-IPC-Cmd ca-certificates tar wget || \
            run_dnf --assumeyes install gcc make perl ca-certificates tar wget
    elif command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update
        $SUDO apt-get install -y build-essential perl curl ca-certificates tar
    else
        echo "ERROR: no package manager available to install build tools."
        exit 1
    fi
        if command -v curl >/dev/null 2>&1; then
            fetcher="curl"
        elif command -v wget >/dev/null 2>&1; then
            fetcher="wget"
        else
            echo "ERROR: curl or wget is required to download OpenSSL."
            exit 1
        fi
    fi

    local workdir
    workdir="$(mktemp -d)"
    (
        cd "$workdir"
        echo "Downloading ${OPENSSL_URL}..."
        if [ "$fetcher" = "curl" ]; then
            curl -fsSL "$OPENSSL_URL" -o openssl.tar.gz
        else
            wget -qO openssl.tar.gz "$OPENSSL_URL"
        fi
        tar -xzf openssl.tar.gz
        cd "openssl-${OPENSSL_VERSION}"
        ./Configure linux64-loongarch64 \
            --prefix="$OPENSSL_PREFIX" \
            --openssldir="$OPENSSL_DIR" \
            --libdir="$OPENSSL_LIBDIR" \
            shared
        make -j"$(nproc)"
        make DESTDIR="$SYSROOT_DIR" install_sw install_ssldirs
    )
    rm -rf "$workdir"
}

build_openssl_debian() {
    $SUDO mkdir -p "$SYSROOT_DIR/tmp"
    cat <<EOD | $SUDO tee "$SYSROOT_DIR/tmp/build_src_libs.sh" >/dev/null
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential perl curl ca-certificates tar
cd /tmp
curl -fsSL "${OPENSSL_URL}" -o openssl.tar.gz
tar -xzf openssl.tar.gz
cd openssl-${OPENSSL_VERSION}
./Configure linux64-loongarch64 --prefix=${OPENSSL_PREFIX} --openssldir=${OPENSSL_DIR} --libdir=${OPENSSL_LIBDIR} shared
make -j\$(nproc)
make install_sw install_ssldirs
apt-get purge -y build-essential perl curl || true
apt-get autoremove -y || true
rm -rf /var/lib/apt/lists/* /tmp/openssl.tar.gz /tmp/openssl-${OPENSSL_VERSION}
EOD
    $SUDO chmod +x "$SYSROOT_DIR/tmp/build_src_libs.sh"
    $SUDO chroot "$SYSROOT_DIR" /bin/bash /tmp/build_src_libs.sh
    $SUDO rm -f "$SYSROOT_DIR/tmp/build_src_libs.sh"
}

echo "=== Building OpenSSL ${OPENSSL_VERSION} (mode=${SRC_BUILD_MODE}) ==="
case "$SRC_BUILD_MODE" in
    debian)
        build_openssl_debian
        ;;
    ocs|native)
        build_openssl_native
        ;;
    *)
        echo "ERROR: Unsupported SRC_BUILD_MODE=$SRC_BUILD_MODE (expected debian|ocs|native)."
        exit 1
        ;;
esac

enable_openssl_legacy_provider
verify_openssl_symbols
