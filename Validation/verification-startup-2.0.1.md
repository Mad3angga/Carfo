# Verifikasi perbaikan startup 2.0.1

26 Oktober 2026. Build 3, arm64. Pengujian memakai direktori data dan UserDefaults suite terpisah dari koleksi pengguna.

- Regresi awal: executable dalam DMG 2.0 langsung berhenti dengan SIGTRAP ketika folder resource SwiftPM pengembang tidak dapat dibaca. Pesannya `Fatal error: could not load resource bundle`. Loader mencari bundle di akar app, sementara packaging menaruhnya di `Contents/Resources`.
- Perbaikan: app terkemas mengambil ikon dan worker dari resource app. `Bundle.module` hanya dipakai pada executable SwiftPM. Pemasangan ikon pada file executable dihapus; worker yang hilang menghasilkan error instalasi.
- PASS: 57 pengujian Swift, tanpa kegagalan, dengan strict concurrency, warnings-as-errors, dan actor data race checks.
- PASS: build release dan verifikasi runtime Python 3.13.14, 83 dependensi. Sebanyak 405 Mach-O bawaan ditandatangani ulang bersama app.
- PASS: smoke test worker offline pada teks, gambar, audio, embedding transkrip, dan Whisper dengan cache kosong. Laporan: `build/offline-smoke.json`.
- PASS: startup app dengan seluruh folder `.build` diblokir dan working directory sementara. Panel pencarian, metadata, dan indeks mencapai tahap siap. Pemeriksaan signature setelah startup lulus dan executable tidak mendapat `com.apple.ResourceFork` atau `com.apple.FinderInfo`. Laporan: `build/startup-smoke.json`.
- PASS: inspeksi antarmuka native dengan `.build` diblokir; ikon termuat, panel pencarian terbuka, `Command+,` membuka Pengaturan dengan versi `Carfo 2.0.1`, tombol Buka pencarian berfungsi, dan `Command+Q` menutup app secara normal.
- PASS: DMG baru lolos checksum, struktur app/symlink Applications, serta uji startup langsung dari app dalam disk image dengan `.build` diblokir. Signature tetap valid setelah startup. Laporan: `build/dmg-startup-smoke.json`.
- PASS: pemeriksaan sintaks skrip Python/zsh dan `git diff --check`.

Artefak: `build/Carfo-2.0.1.dmg`. SHA-256: `1d5d5073e75ea905f349b5903dc215f3a635e8295ba4a6a1e5c29945fc0ab522`. DMG lama disimpan sebagai `build/Carfo-2.0-before-startup-fix.dmg`.

Belum tersedia sertifikat Developer ID pada mesin ini. Signature masih ad hoc; build ini belum notarized dan tidak dinyatakan lolos Gatekeeper untuk distribusi normal. Uji fisik di MacBook Air M5 belum dilakukan. Uji startup memeriksa kemandirian dari folder pengembang pada mesin lokal.
