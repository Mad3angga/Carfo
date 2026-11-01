<p align="center">
  <img src="Assets/Carfo-icon-transparent.png" width="128" height="128" alt="Carfo App Icon">
</p>

<h1 align="center">Carfo</h1>

<p align="center">
  <strong>Cari video, gambar, dan audio di Mac berdasarkan isi medianya secara lokal dan offline.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon-orange" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Privacy-100%25%20Offline-green" alt="100% Offline">
</p>

---

Carfo adalah aplikasi menu bar macOS untuk menemukan footage dari deskripsi adegan, kutipan percakapan, atau bunyi yang Anda ingat. Buka panel pencarian dengan pintasan keyboard, ketik kueri, tinjau hasil dan segmen waktunya melalui preview langsung, lalu buka file asli atau seret ke aplikasi editing Anda.

Seluruh pemrosesan media berjalan sepenuhnya secara lokal di Mac Anda tanpa server cloud atau API eksternal.

## Daftar Isi

- [Fitur Utama](#fitur-utama)
- [Mode Pencarian](#mode-pencarian)
- [Tangkapan Layar](#tangkapan-layar)
- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi](#instalasi)
  - [Unduh File DMG](#1-unduh-file-dmg)
  - [Build dari Source Code](#2-build-dari-source-code)
- [Cara Penggunaan](#cara-penggunaan)
  - [Pintasan Keyboard](#pintasan-keyboard)
- [Privasi dan Penyimpanan](#privasi-dan-penyimpanan)
- [Batasan dan Pemecahan Masalah](#batasan-dan-pemecahan-masalah)
- [Melaporkan Masalah](#melaporkan-masalah)
- [Lisensi](#lisensi)

---

## Fitur Utama

- **Panel Pencarian Mengambang**: Akses cepat bergaya Spotlight dengan pintasan global `⌥Spasi` tanpa perlu meninggalkan aplikasi editing Anda.
- **Pencarian Semantik & Multimodal**: Cari video berdasarkan deskripsi adegan, gambar berdasarkan konten visual, dialog berdasarkan ucapan, serta efek audio berdasarkan kemiripan suara.
- **Preview Terintegrasi**: Tinjau segmen video dan audio langsung pada posisi waktu yang relevan sebelum membuka file aslinya.
- **Drag & Drop ke Editor**: Seret klip hasil pencarian langsung ke timeline editor video (seperti Final Cut Pro, DaVinci Resolve, Premiere Pro) atau Finder.
- **Pencarian Nama File Instan**: File yang telah dipindai dapat langsung dicari berdasarkan nama, bahkan ketika proses pengindeksan isi konten media masih berlangsung.
- **Multi-folder & Subfolder**: Kelola beberapa folder koleksi sekaligus dan gunakan filter pencarian per folder.
- **Pengindeksan Bertahap**: Pengindeksan menyimpan progres secara bertahap dan dapat dijeda atau dilanjutkan kapan saja.
- **100% Lokal & Privat**: Media tidak dikirim ke internet, tidak memerlukan API key, dan tidak memerlukan server tambahan.

---

## Mode Pencarian

| Mode | Media yang dicari | Contoh kueri |
| --- | --- | --- |
| **Video** | Isi visual dan audio dalam klip video | `orang berjalan di pantai` |
| **Gambar** | Konten visual dalam file foto/gambar | `mobil merah di jalan` |
| **Dialog** | Ucapan dalam video/audio, lengkap dengan kutipan dan timestamp | `kita mulai syuting besok` |
| **Suara** | Karakteristik bunyi pada trek audio dan video | `suara hujan dan petir` |

> [!NOTE]
> Kueri di atas adalah contoh penggunaan. Hasil pencarian bergantung pada isi koleksi dan progres pengindeksan media Anda.

---

## Tangkapan Layar

<p align="center">
  <img width="720" alt="Panel Pencarian Carfo" src="https://github.com/user-attachments/assets/9c36a637-381f-457a-9e9c-e4a3b0b31290">
  <br>
  <em>Panel pencarian mengambang bergaya Spotlight untuk mencari klip footage</em>
</p>

<p align="center">
  <img width="720" alt="Hasil Pencarian dan Preview" src="https://github.com/user-attachments/assets/8dcd8992-8e05-4f80-8cc8-3bc0c009af0e">
  <br>
  <em>Hasil pencarian semantik dengan preview video instan dan penanda segmen waktu</em>
</p>

<p align="center">
  <img width="720" alt="Pengaturan Folder Koleksi" src="https://github.com/user-attachments/assets/d9d1de20-8ed2-4a03-bee2-1e3c3da5164a">
  <br>
  <em>Jendela Pengaturan untuk mengelola folder koleksi, indeks, dan pintasan</em>
</p>

---

## Persyaratan Sistem

- Mac dengan chip **Apple Silicon** (M1/M2/M3/M4).
- **macOS 14.0 (Sonoma)** atau lebih baru.
- Ruang penyimpanan untuk aplikasi, basis data indeks, dan thumbnail klip (bergantung pada ukuran koleksi media).

---

## Instalasi

### 1. Unduh File DMG

1. Unduh file `.dmg` Carfo terbaru dari halaman [Releases](https://github.com/Mad3angga/Carfo/releases).
2. Buka file `.dmg` tersebut melalui Finder.
3. Seret `Carfo.app` ke folder **Applications**.
4. Buka Carfo dari folder Applications. Ikon Carfo akan muncul di menu bar.

### 2. Build dari Source Code

Jika ingin mengompilasi dari kode sumber:

```sh
# Clone repositori
git clone https://github.com/Mad3angga/Carfo.git
cd Carfo

# Jalankan suite pengujian
swift test

# Build executable biner
swift build -c release --product Carfo
```

Untuk petunjuk lengkap mengenai pembuatan bundle aplikasi mandiri (`Carfo.app`) beserta runtime Python terisolasi dan model pendukung, lihat [BUILDING.md](BUILDING.md).

---

## Cara Penggunaan

1. Klik ikon Carfo di menu bar atau tekan `⌘,` saat Carfo aktif untuk membuka **Pengaturan**.
2. Klik **Tambah folder** dan pilih folder media Anda. Carfo akan memindai folder dan memulai pengindeksan isi media.
3. Tekan pintasan global `⌥Spasi` untuk membuka panel pencarian dari aplikasi mana pun.
4. Pilih mode pencarian (**Video**, **Gambar**, **Dialog**, atau **Suara**), lalu ketik kueri Anda.
5. Gunakan tombol panah untuk meninjau preview klip dan posisi waktunya. Tekan `Return` untuk membuka file asli, `⌘Return` untuk menampilkan di Finder, atau seret langsung ke aplikasi lain.

Gunakan tombol **Pindai ulang** di Pengaturan setelah menambah atau mengubah file di folder koleksi Anda. Anda dapat menghentikan pengindeksan kapan saja tanpa kehilangan progres yang tersimpan.

### Pintasan Keyboard

| Pintasan | Tindakan |
| --- | --- |
| `⌥Spasi` | Buka atau tutup panel pencarian dari aplikasi mana pun (dapat disesuaikan) |
| `↑` / `↓` | Pilih hasil pencarian sebelumnya atau berikutnya |
| `⌃P` | Putar atau jeda pemutaran preview video/audio |
| `Return` | Buka file asli dengan aplikasi default macOS |
| `⌘Return` | Tampilkan file di Finder |
| `Escape` saat mengetik | Hapus teks kueri; tekan sekali lagi saat kosong untuk menutup panel |
| `⌘,` | Buka jendela Pengaturan |

> Pintasan pembuka global dapat diganti menjadi `⌃⌥Spasi` atau `⌃Spasi` melalui jendela Pengaturan.

---

## Privasi dan Penyimpanan

- **100% Offline**: Seluruh pemrosesan media dan pencarian berjalan di perangkat lokal. Tidak ada data media, transkrip, atau thumbnail yang dikirim ke jaringan luar.
- **Data Tersimpan**: Indeks basis data SQLite, transkrip, thumbnail, dan log disimpan di:
  `~/Library/Application Support/Carfo/`
- **Keamanan File**: File asli di folder koleksi Anda tidak pernah dipindahkan, diubah, atau dihapus. Menghapus folder dari koleksi Carfo hanya membersihkan indeks lokal aplikasi tanpa memengaruhi file fisik Anda.

---

## Batasan dan Pemecahan Masalah

| Kondisi | Penjelasan dan Solusi |
| --- | --- |
| **Hanya nama file yang cocok** | Pengindeksan isi konten masih berjalan di latar belakang. Tunggu hingga selesai atau gunakan tombol *Pindai ulang* jika proses terhenti. |
| **Dialog belum memiliki kutipan** | Tunggu proses transkripsi selesai dan pastikan media memiliki ucapan vokal yang cukup jelas untuk dikenali. |
| **Folder atau file tidak dapat dibuka** | Tambahkan atau pilih ulang folder di Pengaturan untuk memperbarui izin bookmark akses macOS. |
| **File gagal diindeks** | Beberapa format atau codec media yang tidak didukung decoder macOS mungkin dilewati. |
| **Adegan singkat terlewat** | Pengambilan sampel frame dilakukan secara berkala; adegan yang berlangsung sangat singkat (< 1 detik) mungkin terlewat dari sampel visual. |

---

## Melaporkan Masalah

Jika Anda menemukan bug atau kendala penggunaan, silakan buat laporan masalah di [GitHub Issues](https://github.com/Mad3angga/Carfo/issues) dengan menyertakan:
- Versi Carfo dan versi macOS.
- Model Mac / chip Apple Silicon yang digunakan.
- Langkah untuk mereproduksi masalah.
- Format dan codec file media terkait jika menyangkut kegagalan pemrosesan.

---

## Lisensi

Proyek ini dilisensikan di bawah [GNU General Public License v3.0](LICENSE).
