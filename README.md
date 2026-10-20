# Carfo

Aplikasi menu bar macOS untuk mencari footage video berdasarkan gambar, isi percakapan, dan suara. Dibangun dengan SwiftUI dan AppKit mengikuti empat frame desain Pencil milik pengguna.

Pemrosesan selalu memakai **Google Embedding (EmbeddingGemma 2) secara lokal melalui MLX**. Tidak ada API key, server HTTP, pengiriman footage, atau unduhan manual. Model dan runtime sudah siap dan disertakan secara otomatis, sehingga pengaturan model tidak perlu ditampilkan di aplikasi.

## Menjalankan

1. Buka `build/Carfo.app`. Aplikasi juga dapat dipindahkan ke `/Applications`.
2. Buka Pengaturan dengan `⌘,` untuk mengelola folder footage Anda.
3. Klik **Indeks footage**. Proses ini membuat thumbnail dan embedding di Mac.
4. Buka pencarian dengan `⌥Space`, pilih Gambar, Dialog, atau Suara, lalu tulis deskripsi.

Saat koleksi belum diindeks, pencarian tetap dapat mencari nama file. Pencarian semantik menampilkan hasil terdekat dari segmen yang sudah diindeks, tanpa menyajikan skor sebagai persentase kepastian.

## Kebutuhan dan ukuran

- Mac Apple Silicon, macOS 14 atau lebih baru.
- Runtime Python MLX dan model Google EmbeddingGemma 2 (sudah disertakan saat distribusi DMG atau dideteksi otomatis di Mac).
- Aplikasi native ringan dengan konsumsi resource efisien.

Lokasi model dan runtime dideteksi otomatis dari bundle aplikasi (`Contents/Resources/Model`, `Contents/Resources/Python`) maupun cache lokal:

```text
Contents/Resources/Model (di dalam paket aplikasi/DMG)
~/.cache/huggingface/hub/models--google--embeddinggemma-2/snapshots/...
~/.cache/huggingface/hub/models--unsloth--embeddinggemma-2/snapshots/...
~/.unsloth/studio/unsloth_studio/bin/python
```

## Kontrol

| Kontrol | Tindakan |
| --- | --- |
| `⌥Space` | Buka atau tutup pencarian dari aplikasi mana pun |
| `↑` / `↓` | Pilih hasil |
| `Tab`, lalu `Space` pada hasil | Putar atau jeda preview |
| `⌃P` | Putar atau jeda preview saat mengetik |
| `Return` | Buka file asli menggunakan aplikasi default macOS |
| `⌘Return` | Tampilkan file di Finder |
| `Escape` | Tutup panel |
| `⌘,` | Buka pengaturan |
| Klik kanan hasil | Buka file, tampilkan di Finder, atau salin lokasi |
| Seret hasil | Seret file video ke aplikasi lain |

Pintasan pembuka dapat diubah agar tidak mengambil alih `⌘Space` milik Spotlight. Pilihan terang, gelap, dan sistem hanya mengubah tampilan Carfo. Buka saat login menggunakan `SMAppService`; fitur ini tidak otomatis diaktifkan.

## Cara indeks bekerja

Video dibagi menjadi segmen 12 detik. Tiga frame dari setiap segmen diolah bersama oleh encoder visual. Trek audio dipotong menjadi WAV mono 16 kHz dan diolah oleh encoder audio model yang sama. Dialog mencari isi ucapan secara semantik; aplikasi tidak membuat transkrip kata demi kata. Suara mencari kemiripan bunyi atau suasana dari embedding audio.

Embedding 768 dimensi dinormalisasi dan dibandingkan menggunakan cosine similarity. Satu hasil terbaik ditampilkan per file, beserta posisi segmennya. Preview melompat ke segmen tersebut. Membuka file dengan aplikasi lain tetap membuka file asli.

Indeks, thumbnail, dan log mesin disimpan di `~/Library/Application Support/Carfo/`. File asli tidak dipindahkan atau diubah. Progres disimpan sesudah setiap embedding sehingga pengindeksan dapat dilanjutkan setelah dihentikan. Pindai ulang untuk mendeteksi perubahan atau penghapusan video.

Format video mengikuti dukungan decoder macOS, terutama MOV, MP4, dan M4V. File lain yang tidak dapat dibaca dilaporkan. Sampling tiga frame dapat melewatkan peristiwa visual yang sangat singkat; timestamp hasil menunjuk segmen, bukan deteksi batas adegan presisi.

## Build dan pengujian

Tidak ada dependency Swift dari jaringan.

```sh
zsh scripts/build-app.sh
swift test --cache-path .build/Cache --config-path .build/Configuration --security-path .build/Security --disable-sandbox
```

Build menghasilkan aplikasi dengan tanda tangan ad hoc untuk penggunaan lokal. Distribusi publik memerlukan penandatanganan Developer ID dan notarization.

Untuk menyiapkan ulang aplikasi validasi dengan video sintetis:

```sh
python3 scripts/prepare-validation.py
```

Skrip ini memerlukan FFmpeg untuk membuat fixture uji. Buka `.runtime/Carfo Check.app` melalui Finder; hasil akan ditulis ke `.runtime/NativeValidation/self-test.json`.

Referensi model: [dokumentasi Google](https://ai.google.dev/gemma/docs/embeddinggemma), [model Unsloth](https://huggingface.co/unsloth/embeddinggemma-2).
