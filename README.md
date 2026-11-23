<div align="center">
  <img src="Assets/Carfo-icon-transparent.png" width="120" height="120" alt="Ikon Aplikasi Carfo">

  <h1>Carfo</h1>

  <p>
    <strong>Pencarian semantik bergaya Spotlight untuk koleksi video, gambar, dialog, dan audio lokal di Mac — 100% offline.</strong>
  </p>

  <p>
    <a href="https://github.com/Mad3angga/Carfo/releases/latest"><img src="https://img.shields.io/github/v/release/Mad3angga/Carfo?label=Release&color=0866D8" alt="Latest Release"></a>
    <img src="https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple" alt="macOS 14.0+">
    <img src="https://img.shields.io/badge/Apple%20Silicon-M1%20%E2%80%93%20M4-orange" alt="Apple Silicon">
    <img src="https://img.shields.io/badge/Offline-100%25%20Lokal-2ea043" alt="100% Offline">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL-3.0"></a>
  </p>

  <p>
    <a href="https://github.com/Mad3angga/Carfo/releases/latest"><strong>Unduh DMG Terbaru</strong></a>
    &nbsp;·&nbsp;
    <a href="#tangkapan-layar">Tangkapan Layar</a>
    &nbsp;·&nbsp;
    <a href="#cara-penggunaan">Cara Penggunaan</a>
    &nbsp;·&nbsp;
    <a href="#arsitektur-dan-cara-kerja">Arsitektur</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/Mad3angga/Carfo/issues">Laporkan Masalah</a>
  </p>

  <br>

  <img width="780" alt="Hasil Pencarian Semantik dan Preview Carfo" src="https://github.com/user-attachments/assets/8dcd8992-8e05-4f80-8cc8-3bc0c009af0e">
  <br>
  <sub><em>Cari footage berdasarkan adegan, ucapan, atau suara — tinjau langsung pada timestamp yang tepat, lalu seret ke timeline editor Anda.</em></sub>
</div>

---

**Carfo** adalah aplikasi menu bar macOS untuk editor video, kreator konten, dan siapa pun yang mengelola banyak file media lokal. Cukup tekan `⌥Spasi` dari aplikasi mana saja, ketik adegan, kutipan ucapan, atau bunyi yang Anda ingat, lihat pratinjau langsung pada detik yang relevan, lalu buka file asli atau seret klip ke Final Cut Pro, DaVinci Resolve, Premiere Pro, maupun Finder.

Semua proses — mulai dari ekstraksi frame, transkripsi percakapan, hingga pencarian vektor — berjalan sepenuhnya di perangkat Mac Anda tanpa internet, tanpa cloud, dan tanpa API key.

## Daftar Isi

- [Fitur Utama](#fitur-utama)
- [Mode Pencarian](#mode-pencarian)
- [Tangkapan Layar](#tangkapan-layar)
- [Format yang Didukung](#format-yang-didukung)
- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi](#instalasi)
- [Cara Penggunaan](#cara-penggunaan)
- [Pintasan Keyboard](#pintasan-keyboard)
- [Arsitektur dan Cara Kerja](#arsitektur-dan-cara-kerja)
- [Privasi dan Penyimpanan](#privasi-dan-penyimpanan)
- [Pemecahan Masalah](#pemecahan-masalah)
- [Kontribusi & Pelaporan Masalah](#kontribusi--pelaporan-masalah)
- [Lisensi](#lisensi)

---

## Fitur Utama

- **Panel Mengambang Bergaya Spotlight**: Panggil kapan saja dengan pintasan global `⌥Spasi` tanpa meninggalkan jendela aplikasi editing Anda.
- **Pencarian Semantik Multimodal**: Temukan klip tidak hanya dari nama file, melainkan juga dari isi visual video, objek dalam gambar, ucapan dialog, hingga karakteristik suara.
- **Pencarian Instan Dua Tahap**: Kecocokan nama file dan teks tampil seketika saat Anda mengetik, lalu diperkaya oleh hasil semantik secara asinkron tanpa membekukan antarmuka.
- **Preview Langsung di Timestamp**: Putar segmen video atau audio tepat di bagian yang cocok sebelum membuka file aslinya.
- **Drag & Drop ke Aplikasi Editing**: Seret hasil pencarian langsung ke timeline **Final Cut Pro**, **DaVinci Resolve**, **Premiere Pro**, atau **Finder**.
- **Dukungan Subtitle Sidecar (`.srt` & `.vtt`)**: Subtitle yang sudah tersedia di sebelah video otomatis dibaca untuk pencarian dialog dan dideteksi ulang bila isinya berubah.
- **Tahan Rename & Pindah Folder**: Mengganti nama file atau memindahkannya ke subfolder dalam koleksi tidak memicu pengindeksan ulang — embedding, transkrip, dan thumbnail tetap dipertahankan.
- **Pengindeksan Bertahap & Dapat Dijeda**: Progres disimpan secara inkremental ke SQLite sehingga aman dihentikan dan dilanjutkan kapan saja tanpa mengulang segmen yang sudah selesai.

---

## Mode Pencarian

| Mode | Cakupan Media | Contoh Kueri |
| --- | --- | --- |
| **Video** | Isi visual dan audio pada klip video | `orang berjalan di pantai`, `lampu kota malam` |
| **Gambar** | Konten visual dalam foto, ilustrasi, dan vektor | `mobil merah di jalan`, `meja kerja minimalis` |
| **Dialog** | Ucapan dalam video/audio beserta kutipan & timestamp | `kita mulai syuting besok`, `istirahat dulu` |
| **Suara** | Karakteristik bunyi, musik, dan suasana audio | `suara hujan dan petir`, `burung berkicau` |

> [!TIP]
> Anda dapat mencari dalam bahasa Indonesia maupun bahasa Inggris, serta mempersempit hasil ke folder koleksi tertentu langsung dari bilah atas panel pencarian.

---

## Tangkapan Layar

<p align="center">
  <img width="740" alt="Panel Pencarian Carfo" src="https://github.com/user-attachments/assets/9c36a637-381f-457a-9e9c-e4a3b0b31290">
  <br>
  <sub><strong>Panel Pencarian Cepat</strong> — Muncul mengambang di atas aplikasi apa pun dengan pintasan <code>⌥Spasi</code>.</sub>
</p>

<br>

<p align="center">
  <img width="740" alt="Pengaturan Folder Koleksi" src="https://github.com/user-attachments/assets/d9d1de20-8ed2-4a03-bee2-1e3c3da5164a">
  <br>
  <sub><strong>Pengaturan Koleksi</strong> — Kelola banyak folder beserta subfolder, tema terang/gelap, dan pintasan global.</sub>
</p>

---

## Format yang Didukung

| Kategori | Ekstensi |
| --- | --- |
| **Video** | `.mov`, `.mp4`, `.m4v`, `.mkv`, `.avi`, `.webm` |
| **Gambar** | `.png`, `.jpg`, `.jpeg`, `.webp`, `.heic`, `.heif`, `.svg`, `.avif`, `.gif`, `.tiff`, `.tif`, `.bmp`, `.ico` |
| **Audio** | `.mp3`, `.wav`, `.aac`, `.m4a`, `.flac`, `.ogg`, `.aiff`, `.aif`, `.opus`, `.wma` |
| **Subtitle Sidecar** | `.srt`, `.vtt` *(otomatis terdeteksi jika bernama sama dengan file video/audio)* |

---

## Persyaratan Sistem

- **Chip**: Mac dengan **Apple Silicon** (`M1` / `M2` / `M3` / `M4`).
- **Sistem Operasi**: **macOS 14.0 (Sonoma)** atau lebih baru.
- **Penyimpanan**: Ruang kosong untuk aplikasi beserta indeks SQLite dan thumbnail klip (menyesuaikan jumlah koleksi media Anda).

---

## Instalasi

### Opsi 1: Unduh File DMG *(Direkomendasikan)*

1. Unduh file `Carfo.dmg` terbaru dari halaman [GitHub Releases](https://github.com/Mad3angga/Carfo/releases/latest).
2. Buka `Carfo.dmg` melalui Finder, lalu seret **Carfo.app** ke folder **Applications**.
3. Jalankan **Carfo** dari folder Applications — ikon Carfo akan muncul di menu bar macOS.

<details>
<summary><strong>Catatan macOS Gatekeeper (jika muncul peringatan pengembang tidak dikenal)</strong></summary>

Jika build yang diunduh belum melalui notarization Developer ID, klik kanan pada `Carfo.app` di folder **Applications** → pilih **Open** → konfirmasi **Open** pada dialog yang muncul (cukup sekali saat pertama kali dibuka).

</details>

### Opsi 2: Build dari Source Code

```sh
# 1. Clone repositori
git clone https://github.com/Mad3angga/Carfo.git
cd Carfo

# 2. Jalankan seluruh unit & workflow test (strict concurrency)
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

# 3. Build biner release
swift build -c release --product Carfo
```

Untuk panduan lengkap merakit bundle mandiri `Carfo.app` beserta runtime Python terisolasi, model MLX, dan pembuatan DMG, lihat [BUILDING.md](BUILDING.md). Riwayat perubahan tiap versi tersedia di [CHANGELOG.md](CHANGELOG.md).

---

## Cara Penggunaan

1. **Tambahkan Folder Koleksi**: Klik ikon Carfo di menu bar (atau tekan `⌘,`), buka **Pengaturan**, lalu klik **Tambah folder**. Carfo akan langsung memindai file media dan memulai pengindeksan di latar belakang.
2. **Buka Panel Pencarian**: Tekan `⌥Spasi` dari aplikasi mana pun.
3. **Pilih Mode & Ketik Kueri**: Pilih tab **Video**, **Gambar**, **Dialog**, atau **Suara**, lalu ketik deskripsi yang dicari.
4. **Tinjau & Gunakan Klip**:
   - Navigasi daftar dengan `↑` / `↓` untuk melihat preview di sisi kanan.
   - Tekan `⌃P` untuk memutar/menjeda preview tepat pada segmen waktu hasil pencarian.
   - Tekan `Return` untuk membuka file asli, `⌘Return` untuk menampilkannya di Finder, atau **seret langsung** klip dari daftar/preview ke editor video Anda.
5. **Perbarui Koleksi**: Setelah menambah atau mengubah media di folder, klik **Pindai ulang** di Pengaturan. Proses bisa dihentikan kapan saja dan dilanjutkan tanpa mengulang progres yang sudah tersimpan.

---

## Pintasan Keyboard

| Pintasan | Tindakan |
| --- | --- |
| `⌥Spasi` | Buka atau tutup panel pencarian dari aplikasi mana pun *(bisa diganti ke `⌃⌥Spasi` atau `⌃Spasi`)* |
| `↑` / `↓` | Pindah ke hasil pencarian sebelumnya atau berikutnya |
| `⌃P` | Putar atau jeda preview video/audio pada timestamp yang cocok |
| `Return` | Buka file asli dengan aplikasi default macOS |
| `⌘Return` | Tampilkan lokasi file di Finder |
| `Escape` | Hapus teks pencarian; tekan lagi saat kosong untuk menutup panel |
| `⌘,` | Buka jendela Pengaturan |
| `⌘Q` | Keluar dari Carfo |

---

## Arsitektur dan Cara Kerja

Carfo memadukan antarmuka macOS native dengan mesin inferensi lokal berakselerasi Apple Silicon:

- **Aplikasi Native (Swift + SwiftUI + AppKit)**: Panel mengambang `NSPanel`, decoding media native dengan `AVFoundation` (ekstraksi frame berkelompok & audio PCM 16 kHz streaming), serta perhitungan kemiripan kosinus berbasis SIMD menggunakan **Accelerate `vDSP`**.
- **Embedding Multimodal Lokal (`EmbeddingGemma 2` via MLX)**: Memetakan teks, frame video/gambar, dan segmen audio ke ruang vektor 768 dimensi yang sama di GPU/Neural Engine Apple Silicon.
- **Transkripsi Ucapan Offline (`Whisper` via `mlx-whisper`)**: Mentranskripsikan dialog per potongan 60 detik dengan overlap agar hemat memori, mendukung resume dari offset terakhir, dan menghasilkan timestamp tingkat kalimat.
- **Penyimpanan Inkremental (SQLite WAL)**: Metadata klip, vektor biner, transkrip, dan status progres disimpan per record di SQLite dengan cadangan atomik.

```text
Sources/
├── Carfo/              # Aplikasi macOS (menu bar, panel Spotlight, preview, Pengaturan, AppModel)
│   └── Resources/Engine/worker.py  # Worker MLX lokal (EmbeddingGemma 2 + Whisper) via pipe stdin/stdout
├── CarfoCore/          # Core engine (LibraryDatabase SQLite, MediaProcessor, SearchEngine, LocalEngine)
└── CarfoBenchmark/     # Utilitas benchmark indeks, media, dan audio
```

---

## Privasi dan Penyimpanan

- **100% Lokal & Privat**: Tidak ada koneksi ke internet, server eksternal, atau telemetri. Semua file media, transkrip, dan vektor tetap berada di Mac Anda.
- **Lokasi Data Aplikasi**: Indeks SQLite, cadangan indeks, thumbnail, dan log tersimpan di:
  ```text
  ~/Library/Application Support/Carfo/
  ```
- **File Asli Tetap Aman**: Carfo hanya membaca folder koleksi Anda dan tidak pernah memindahkan, mengubah, atau menghapus file fisik. Mengeluarkan folder dari Pengaturan hanya menghapus indeksnya di Carfo.

---

## Pemecahan Masalah

| Kondisi | Penyebab & Solusi |
| --- | --- |
| **Baru nama file yang muncul di hasil** | Pengindeksan isi visual/audio masih berjalan di latar belakang. Tunggu hingga selesai atau klik **Pindai ulang** jika sempat dijeda. |
| **Mode Dialog belum menampilkan kutipan** | Transkripsi audio masih berlangsung, atau klip tidak memiliki ucapan yang cukup jelas. Jika sudah punya file `.srt`/`.vtt`, letakkan di sebelah file video dengan nama sama. |
| **Folder atau file tidak bisa dibuka** | Izin akses bookmark macOS perlu diperbarui — pilih ulang folder tersebut lewat Pengaturan. |
| **Sebagian file dilewati saat indexing** | Beberapa codec yang tidak didukung decoder bawaan macOS dapat gagal diproses; Carfo mencatat error pada klip tersebut dan tetap melanjutkan file lainnya. |
| **Adegan sangat singkat terlewat** | Sampel frame diambil secara berkala per segmen video sehingga objek yang muncul kurang dari 1 detik berpotensi terlewat. |

---

## Kontribusi & Pelaporan Masalah

Menemukan bug atau punya ide fitur? Silakan buka laporan di [GitHub Issues](https://github.com/Mad3angga/Carfo/issues) dengan menyertakan:

- Versi **Carfo** dan versi **macOS**.
- Model Mac / chip Apple Silicon yang dipakai.
- Langkah singkat untuk mereproduksi kendala.
- Format dan codec media terkait *(jika menyangkut kegagalan pemrosesan)*.

---

## Lisensi

Carfo adalah perangkat lunak bebas yang dilisensikan di bawah [GNU General Public License v3.0](LICENSE).
