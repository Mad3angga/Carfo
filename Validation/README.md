# Verifikasi dan benchmark 2.0

`benchmark-2.0.json` adalah baseline release lokal pada 22 Oktober 2026, arm64, 8 CPU, RAM 16 GiB, macOS 26.6.2. Koleksi sintetis berisi 100/500/1.000 video, masing-masing 10 segmen dengan vektor visual/audio 768 dimensi. Pencarian memakai median tujuh pengukuran. Basis data dibuat baru; cache filesystem OS tidak dikosongkan. Ini bukan benchmark kualitas model.

```sh
swift run -c release CarfoBenchmark Validation/benchmark-current.json build/Carfo.app
```

Argumen bundle opsional menambahkan pengukuran model dingin, kueri hangat, pencarian setelah idle paksa, dan pembatalan. Idle dipersingkat menjadi 0,1 detik khusus benchmark; produksi memakai 300 detik. Waktu setelah idle mencakup pemuatan ulang model. `peakRSSBytes` hanya mengukur proses benchmark Swift dan belum mencakup worker Python. Jangan mengartikannya sebagai RAM puncak indexing audio panjang.

| Pengukuran, 1.000 video | Baseline |
| --- | ---: |
| Metadata tanpa embedding | 1,88 ms |
| Indeks SQLite lengkap | 149 ms |
| Hasil teks dari indeks memori | 8,90 ms |
| Ranking vektor dari indeks memori | 30,09 ms |
| Pembaruan satu segmen | 10,50 ms |
| Pembaruan statistik satu clip | 0,00125 ms |
| Model siap dari worker baru | 4.683 ms |
| Kueri model hangat | 199 ms |
| Kueri setelah idle paksa | 4.027 ms |
| Pembatalan worker aktif | 0,10 ms |

Hasil pencarian teks tidak menunggu model. Kebijakan idle diperpanjang dari 45 menjadi 300 detik untuk mengurangi pemuatan ulang yang memerlukan sekitar empat detik pada pengukuran ini. Konsekuensinya, model dapat bertahan di memori lebih lama. Evaluasi penggunaan energi dan RAM model jangka panjang masih terbuka.

Saat aplikasi berjalan, `startup-timings.json` dalam direktori data mencatat `searchViewAppearedMS`, `metadataReadyMS`, dan `indexReadyMS`. Pengukuran dimulai ketika AppModel dibuat. `searchViewAppearedMS` adalah lifecycle SwiftUI, bukan ukuran waktu dari klik ikon sampai frame pertama di layar. Jalur error dan pembatalan diuji terpisah.

## Batas verifikasi

- `media-benchmark-2.0.json` membandingkan generator asinkron terpisah per frame dengan batch asinkron yang dipakai kembali per file. Enam fixture H.264/HEVC/ProRes pada 640×360 dan 1920×1080 berhasil, dengan toleransi timestamp 100 ms. Median batch sekitar 31–67 ms untuk enam frame, versus 68–216 ms pada pembanding; RSS proses benchmark sekitar 29,2 MiB. Ini mengukur reuse/batching dengan JPEG writing, bukan membandingkan langsung API sinkron lama yang deprecated.
- Transkripsi memakai potongan inti 60 detik dengan konteks dua detik di kedua sisi. Cue dimiliki potongan berdasarkan titik tengahnya; timestamp disesuaikan ke file asli. Uji regresi memastikan satu cue batas tidak terduplikasi dan kegagalan potongan kedua dilanjutkan dari offset 60 detik. Perbedaan segmentasi Whisper pada percakapan nyata masih perlu dievaluasi.
- WAV ditulis langsung per buffer; batas empat jam diperiksa sebelum ekstraksi transkrip. `audio-benchmark-2.0.json` mengukur ekstraksi audio sintetis 20 menit dalam proses baru: WAV 38.400.044 byte, 119 ms, RSS puncak 28.540.928 byte (27,2 MiB). Ini belum mengukur RAM worker Whisper atau throughput indexing penuh.
- Pengujian cache thumbnail memeriksa pemuatan asinkron, ukuran 64 versus 640 pt, dan perubahan isi file pada URL yang sama.
- CI menjalankan strict concurrency dengan warnings-as-errors dan actor data race checks. Thread Sanitizer serta profiling main thread dengan Instruments belum menjadi bukti yang tersedia dalam sesi ini.

## Kalibrasi retrieval yang masih terbuka

Pengguna menyatakan belum ada koleksi media berlabel dan meminta CF-15 tetap terbuka. Ranking kini menambah sinyal nama file, memprioritaskan nama persis, serta menolak skor semantik negatif/rendah. Floor umum 0,2 dan floor dialog 0,78 masih bersifat sementara. Tidak ada klaim bahwa threshold tersebut sudah terkalibrasi pada koleksi nyata.

Siapkan video/audio/gambar dengan kueri Indonesia dan Inggris, ucapan bising, bunyi lingkungan, adegan singkat, kecocokan nama persis, dan kueri tanpa hasil. Catat ID file benar, rentang timestamp benar, mode pencarian, serta kondisi indeks/model. Ukur Recall@5, ketepatan hasil teratas, false positive kueri kosong kecocokan, dan kesalahan timestamp sebelum mengubah threshold.

Baseline berikutnya harus dibandingkan pada perangkat, build release, koleksi, dan kondisi cache yang sama. Batas awal untuk investigasi regresi: kenaikan median indeks lebih dari 2× baseline ditambah 5 ms, atau statistik satu clip lebih dari 1 ms. Batas ini merupakan acuan pengembangan awal; throughput media, RAM worker, dan kualitas retrieval belum memiliki batas rilis.

Untuk mengulangi pengukuran codec dan audio tanpa file pribadi:

```sh
python3 scripts/prepare-media-benchmarks.py
swift run -c release CarfoBenchmark --media .runtime/BenchMedia Validation/media-current.json
swift run -c release CarfoBenchmark --audio .runtime/BenchMedia/long.wav Validation/audio-current.json
```
