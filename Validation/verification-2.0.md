# Verifikasi kandidat Carfo 2.0

Tanggal: 22 Oktober 2026. Semua pengujian memakai fixture atau direktori terpisah dari koleksi pengguna.

- **PASS pengujian:** suite 56 pengujian lulus, diikuti satu regresi pergantian model yang juga lulus, dengan `-strict-concurrency=complete`, `-warnings-as-errors`, dan `-enable-actor-data-race-checks`. Total 57 pengujian berbeda, termasuk delapan workflow AppModel, worker palsu, serta AVFoundation.
- **PASS build:** executable release berhasil dibangun. Bundle memuat Python 3.13.14 dengan 83 dependensi wajib yang tervalidasi.
- **PASS offline:** smoke test menjalankan `verify`, `text`, `images`, `audio`, `texts`, dan `transcribe`, memakai resource bundle serta direktori cache kosong.
- **PASS DMG lokal:** checksum `hdiutil verify` valid; DMG dipasang sementara, struktur aplikasi/symlink Applications diperiksa, dan signature aplikasi di dalamnya lulus `codesign --verify --deep --strict`. Ukuran sekitar 1,9 GiB, kompresi level 1. SHA-256: `f2d8106c24948cf6f9f7ac1e565e7fad5ba9663c85dd4ed19d1ab81ad7b8e031`.
- **PASS media:** enam fixture H.264/HEVC/ProRes pada 360p/1080p berhasil diambil melalui batch dengan validasi timestamp 100 ms. Audio sintetis 20 menit berhasil diekstrak secara streaming.
- **PASS UI teramati:** aplikasi dibuka dengan `CARFO_DATA_DIR` dan UserDefaults suite terpisah; pengetikan kueri, perubahan mode Video/Gambar/Dialog/Suara, pintasan `⌘,`, dan tampilan Pengaturan berlabel `Carfo 2.0` diperiksa melalui antarmuka native. Jendela uji ditutup setelah pemeriksaan.
- **PASS scope source:** `git diff --check`, pemeriksaan sintaks zsh, dan kompilasi skrip Python berhasil. Tidak ada commit atau publikasi yang dibuat oleh pekerjaan ini.

## Gate antislop pada perubahan antarmuka

- **Hard Gate PASS:** perubahan menampilkan tahap startup dan versi aktual. Tidak menambah aset, testimoni, atau klaim pengguna. Pengujian memastikan cache thumbnail, empty state tanpa vektor, dan pencarian teks memiliki perilaku nyata; inspeksi native menunjukkan pengaturan dan label versi terbaca tanpa teks keluar container.
- **Purpose Gate PASS:** komposisi, warna, tipografi, simbol native, dan material mengikuti `DESIGN.md`; pekerjaan ini tidak menambahkan teknik dekoratif.
- **Liveliness PASS:** arah yang dipertahankan adalah utilitas menu bar untuk pencarian media lokal, bahasa Spotlight native, ENERGY 1 / RHYTHM 1 / MOTION 1. Kolom pencarian tetap fokus; aksen menandai mode/pilihan aktif.
- **Craftsmanship PASS:** cache memiliki invalidasi versi/ukuran yang diuji; hasil kueri lama tidak menimpa kueri terbaru; startup rusak tidak menyimpan indeks kosong. Pemeriksaan ini mencakup permukaan yang berubah dan bukan audit aksesibilitas ulang seluruh aplikasi.

## Verifikasi yang belum tersedia

Developer ID, notarization produksi, stapling produksi, dan instalasi Mac bersih belum dijalankan karena mesin tidak memiliki identitas signing valid. Kalibrasi retrieval menunggu koleksi berlabel sesuai keputusan pengguna. Profil main thread Instruments, RAM worker pada indexing panjang, throughput indexing penuh, serta batas rilis untuk metrik tersebut tetap dicatat di CF-20.
