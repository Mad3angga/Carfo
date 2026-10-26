# Build Carfo 2.0

Bundle yang dihasilkan memakai Apple Silicon dan minimum macOS 14.0. Target Swift tetap macOS 14 untuk pengujian core. Skrip memeriksa deployment target seluruh Mach-O terhadap `Info.plist` dan menormalkan minos library biner bawaan.

## Runtime yang dapat dibuat ulang

Gunakan distribusi CPython standalone 3.13.14 arm64 yang dapat direlokasi, bukan virtual environment dengan symlink ke Python sistem. Sumber model dan runtime wajib diberikan oleh pembuat bundle. Tidak ada path akun pribadi dalam skrip packaging.

```sh
PYTHON_BASE=/path/to/standalone-python
"$PYTHON_BASE/bin/python3" -m pip install --only-binary=:all: \
  --target .runtime/packages -r Support/requirements-runtime.txt
python3 scripts/prepare-runtime.py "$PYTHON_BASE" .runtime/packages .runtime/Python
.runtime/Python/bin/python3 -I scripts/runtime-manifest.py verify Support/runtime-lock.json

MODEL_SRC=/path/to/embedding-snapshot \
WHISPER_SRC=/path/to/whisper-snapshot \
PYTHON_RUNTIME_SRC="$PWD/.runtime/Python" \
zsh scripts/build-app.sh
```

`Support/runtime-lock.json` mengunci Python, arsitektur, dan 83 distribusi dalam dependency closure worker. `Support/requirements-runtime.txt` berisi pin seluruh closure. Paket aplikasi lain dari runtime lama tidak disalin. Distribusi Python dasar tetap input eksternal; untuk build produksi, arsipkan sumbernya beserta SHA-256 di sistem artefak build.

`scripts/runtime-manifest.py record` hanya digunakan ketika sengaja memperbarui dependensi, setelah resolver dan uji offline lulus. Packaging memakai `verify` dan gagal jika closure, Python, arsitektur, import wajib, model, atau resource tidak lengkap. Mode default menghasilkan signature ad hoc untuk pengujian lokal.

Setiap bundle memuat `build-manifest.json`, identitas model dari hash seluruh berkas, versi prompt/preprocessing, dan runtime lock. Worker dijalankan dengan Python isolated mode; `PYTHONPATH`, `PYTHONHOME`, user site-packages, dan cache model host tidak diperlukan. Smoke test memakai cache kosong dan mode offline untuk teks, gambar, suara, embedding transkrip, serta Whisper.

## Distribusi Developer ID

```sh
MODEL_SRC=/path/to/embedding-snapshot \
WHISPER_SRC=/path/to/whisper-snapshot \
PYTHON_RUNTIME_SRC=/path/to/standalone-runtime \
SIGNING_IDENTITY='Developer ID Application: Nama (TEAMID)' \
NOTARY_PROFILE=carfo-notary DISTRIBUTION=1 zsh scripts/build-app.sh

SIGNING_IDENTITY='Developer ID Application: Nama (TEAMID)' \
NOTARY_PROFILE=carfo-notary DISTRIBUTION=1 zsh scripts/build-dmg.sh
```

Siapkan sertifikat dan profil keychain `notarytool` di mesin rilis. Semua Mach-O ditandatangani sebelum bundle, dengan hardened runtime; executable Python mendapat izin JIT dan executable memory. Mode distribusi mewajibkan notarization, stapling, signature verification, dan penilaian Gatekeeper. Kegagalan menghentikan build. DMG diperiksa integritasnya, dipasang, dan signature aplikasi di dalamnya diverifikasi kembali.

Mesin pengembangan saat implementasi tidak memiliki identitas codesigning yang valid. Build ad hoc yang lolos verifikasi lokal belum membuktikan kelulusan Developer ID, notarization, atau instalasi di Mac bersih.

Packaging juga menjalankan `scripts/smoke-startup.py` pada app yang sudah ditandatangani. Uji ini memblokir pembacaan folder `.build`, memakai direktori data sementara, menunggu panel pencarian dan indeks siap, lalu memastikan signature tetap valid setelah startup. Jalankan build dari sesi desktop macOS aktif. Resource app dibaca dari `Contents/Resources`; `Bundle.module` hanya digunakan saat menjalankan executable SwiftPM.

`DMG_COMPRESSION_LEVEL` menerima nilai 1–9, default 6. Gunakan level 1 untuk verifikasi lokal yang lebih cepat; pengaturan ini memengaruhi ukuran/waktu kompresi dan tidak mengubah isi aplikasi.

## Pengujian

```sh
swift test -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors -Xswiftc -enable-actor-data-race-checks
swift build -c release --product Carfo
```

CI menghasilkan fixture H.264 dan audio sintetis dengan FFmpeg. Pengujian worker memakai Python sistem dengan protokol palsu dan tidak memerlukan MLX, model, atau path media pribadi. Pengujian AppModel memakai directory, UserDefaults suite, instalasi, dan worker yang disuntikkan untuk isolasi.
