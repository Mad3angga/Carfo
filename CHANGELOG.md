# Changelog

## 2.0.1 · 26 Oktober 2026 · Perbaikan startup

- Resource pada app terkemas dibaca dari `Contents/Resources`, sehingga startup tidak bergantung pada folder build komputer pengembang.
- Startup tidak lagi memasang ikon pada file executable, yang dapat membuat signature tidak valid.
- Worker yang hilang dilaporkan sebagai error instalasi tanpa force unwrap.
- Packaging menguji startup dengan folder `.build` diblokir dan memverifikasi signature setelah app berjalan.
- Versi aplikasi menjadi **2.0.1**, build **3**. Developer ID dan notarization tetap diperlukan untuk distribusi normal.

## 2.0 · 22 Oktober 2026 · Kandidat lokal

### Perubahan

- Antarmuka dapat tampil sebelum indeks selesai dibaca. Metadata nama file dimuat lebih dahulu; pemuatan embedding berlangsung di latar belakang dengan status tahap startup.
- Statistik clip diperbarui berdasarkan perubahan, pemetaan ID dipertahankan selama batch scan, dan jumlah file folder memakai hitungan tersimpan.
- Frame video diambil melalui API asinkron berkelompok dengan decoder yang dipakai kembali per file, toleransi 100 ms, serta pembatalan permintaan.
- Audio PCM ditulis langsung ke WAV. Transkripsi memakai potongan 60 detik dengan overlap, menyimpan offset progres, dan melanjutkan potongan yang gagal.
- Subtitle SRT/VTT dipertahankan. Perubahan subtitle terdeteksi melalui fingerprint isi; VTT mendukung cue identifier dan pengaturan setelah timestamp.
- Nama file ikut memengaruhi ranking semantik; nama persis mendapat prioritas. Hasil dengan skor negatif/rendah disaring.
- Thumbnail dibaca di latar belakang dengan cache berdasarkan versi file dan ukuran tujuan. Preview besar tidak menggunakan entri cache kecil.
- Model bertahan hingga lima menit saat idle. Pembatalan menghentikan worker aktif; jalur error menjadwalkan pelepasan resource.
- Packaging memakai sumber model/runtime yang eksplisit, dependency lock, hash model, pemeriksaan deployment target, dan smoke test offline seluruh mode.
- Tersedia alur Developer ID signing, hardened runtime, notarization, stapling, serta pemeriksaan signature aplikasi dan DMG.
- Pengujian AppModel mencakup startup rusak, persist/shutdown, folder, subtitle tanpa Whisper, kegagalan transkripsi per potongan, kueri terbaru, dan invalidasi thumbnail. CI menjalankan strict concurrency dengan warnings-as-errors.
- Benchmark indeks dan inferensi tersimpan di `Validation/benchmark-2.0.json`.

### Kompatibilitas

- Versi aplikasi menjadi **2.0**, build **2**. Versi format indeks tetap 1; metadata progres transkripsi ditambahkan secara kompatibel.
- Bundle runtime mendukung **Apple Silicon dan macOS 14.0+**; minos library dinormalkan ke macOS 14.
- Identitas model kini berasal dari hash berkas dan kontrak preprocessing. Indeks dari identitas berbeda perlu membangun ulang embedding; teks transkrip tetap dipertahankan.

### Status verifikasi

- 57 pengujian lokal lulus dengan strict concurrency, warnings-as-errors, dan actor data race checks.
- Build release dan signature ad hoc lokal lulus; smoke test offline mencakup teks, gambar, audio, embedding transkrip, dan Whisper dengan cache kosong.
- DMG lokal berhasil dibuat, checksum valid, dan signature aplikasi di dalam DMG yang terpasang lulus pemeriksaan.
- CF-15 tetap terbuka karena koleksi media berlabel belum tersedia, sesuai keputusan pengguna.
- CF-18 belum dapat dinyatakan selesai: mesin ini tidak memiliki sertifikat Developer ID; notarization, stapling produksi, dan instalasi di Mac bersih belum diuji.
- Pengujian H.264/HEVC/ProRes pada 360p dan 1080p serta pengukuran RAM ekstraksi audio 20 menit tersimpan. Profiling Instruments, RAM worker saat indexing panjang, dan sebagian kriteria benchmark CF-20 masih terbuka. Rinciannya ada dalam `PERBAIKAN.md` dan `Validation/README.md`.
