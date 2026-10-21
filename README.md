<p align="center">
  <img src="Sources/Carfo/Resources/CarfoIcon.png" alt="Ikon Carfo" width="112">
</p>

# Carfo

Cari video, gambar, dan audio di Mac berdasarkan isi medianya.

Carfo adalah aplikasi menu bar macOS untuk menemukan footage dari deskripsi adegan, kutipan percakapan, atau bunyi yang Anda ingat. Buka panel pencarian, ketik kueri, lalu tinjau hasil dan posisi waktunya sebelum membuka file asli.

Antarmuka dibangun dengan SwiftUI dan AppKit. Pencarian semantik memakai EmbeddingGemma 2 melalui MLX, sedangkan transkripsi dialog memakai Whisper lokal. Pemrosesan berjalan di Mac tanpa API key atau server HTTP. Setelah model dan runtime tersedia, Carfo dapat digunakan secara offline.

## Mode pencarian

| Mode | Media yang dicari | Contoh kueri |
| --- | --- | --- |
| Video | Isi visual dan audio dalam video | `orang berjalan di pantai` |
| Gambar | Isi file gambar | `mobil merah di jalan` |
| Dialog | Ucapan dalam video atau audio, dengan kutipan dan timestamp jika transkrip tersedia | `kita mulai syuting besok` |
| Suara | Bunyi dalam file audio dan video yang memiliki trek audio | `suara hujan dan petir` |

Kueri di atas adalah contoh penggunaan. Hasil bergantung pada koleksi media, indeks, dan model yang tersedia di Mac Anda.

## Fitur

- Panel pencarian mengambang dengan pintasan global `⌥Spasi`.
- Koleksi dari beberapa folder beserta subfoldernya, dengan filter pencarian per folder.
- Pencarian nama file dan lokasi relatif setelah pemindaian, termasuk saat embedding belum tersedia.
- Pencarian dialog berdasarkan kata atau kemiripan makna, dengan konteks percakapan di sekitar kutipan.
- Preview video dan audio pada segmen yang ditemukan, akses ke Finder, serta seret file ke aplikasi lain.
- Pengindeksan bertahap yang menyimpan progres dan dapat dilanjutkan setelah dihentikan.
- Tema terang, gelap, atau mengikuti sistem, serta pilihan membuka aplikasi saat login.

## Persyaratan

- Mac dengan Apple Silicon dan macOS 14 atau lebih baru.
- Model EmbeddingGemma 2 dan runtime Python yang mendukung `mlx`, `mlx-vlm`, NumPy, serta Pillow untuk pencarian semantik.
- Model Whisper lokal dan paket `mlx-whisper` untuk membuat transkrip dialog.
- Swift toolchain 6.0 atau lebih baru untuk build dari source.

Model dan runtime dapat disertakan dalam paket aplikasi atau ditemukan dari instalasi lokal. Carfo tidak mengunduh maupun memasangnya secara otomatis. Kebutuhan ruang penyimpanan dan memori bergantung pada model serta ukuran koleksi.

## Menggunakan aplikasi

Jika sudah memiliki paket `Carfo.app` yang lengkap:

1. Pindahkan `Carfo.app` ke folder Applications, lalu buka aplikasi. Carfo muncul di menu bar.
2. Klik ikon Carfo dan buka Pengaturan. Saat Carfo aktif, Anda juga dapat memakai `⌘,`.
3. Klik **Tambah folder** dan pilih folder media. Carfo memindai file dan memulai pengindeksan bila model serta runtime ditemukan.
4. Tunggu pengindeksan selesai untuk mencari berdasarkan isi media. Selama itu, file yang sudah dipindai dapat dicari berdasarkan namanya.
5. Tekan `⌥Spasi`, pilih mode pencarian, lalu ketik kueri.
6. Pilih hasil untuk meninjau preview. Tekan `Return` untuk membuka file asli atau `⌘Return` untuk menampilkannya di Finder.

Gunakan **Pindai ulang** di Pengaturan setelah menambah, mengubah, atau menghapus media di folder koleksi. Tombol ini juga melanjutkan pengindeksan file yang belum selesai bila mesin lokal tersedia. Mengeluarkan folder dari koleksi tidak menghapus file aslinya.

### Pintasan

Selain pintasan global pembuka, kontrol berikut berlaku saat panel Carfo aktif.

| Pintasan | Tindakan |
| --- | --- |
| `⌥Spasi` | Buka atau tutup panel pencarian dari aplikasi lain |
| `↑` / `↓` | Pilih hasil sebelumnya atau berikutnya |
| `⌃P` | Putar atau jeda preview video/audio |
| `Return` | Buka file asli dengan aplikasi default macOS |
| `⌘Return` | Tampilkan file di Finder |
| `Escape` saat mengetik | Hapus kueri; tutup panel bila kueri sudah kosong |
| `⌘,` | Buka Pengaturan |

Pintasan pembuka dapat diganti menjadi `⌃⌥Spasi` atau `⌃Spasi` di Pengaturan. Klik kanan pada hasil untuk tindakan file; hasil dialog juga menyediakan salinan kutipan.

## Model dan runtime lokal

Carfo memeriksa lokasi bundle aplikasi, folder Application Support, dan cache model lokal. Beberapa lokasi yang dikenali:

| Komponen | Di dalam `Carfo.app` | Lokasi lokal lainnya |
| --- | --- | --- |
| EmbeddingGemma 2 | `Contents/Resources/Model/` | `~/Library/Application Support/Carfo/Model/` atau cache Hugging Face `google/embeddinggemma-2` dan `unsloth/embeddinggemma-2` |
| Python | `Contents/Resources/Python/bin/python` atau `python3` | `~/.unsloth/studio/unsloth_studio/bin/python` atau `~/.unsloth/studio/.venv/bin/python` |
| Whisper | `Contents/Resources/Whisper/` | `~/Library/Application Support/Carfo/Whisper/` atau cache Hugging Face `mlx-community/whisper-small-mlx`, `whisper-large-v3-turbo`, dan `whisper-base-mlx` |

Cache Hugging Face dibaca dari `~/.cache/huggingface/hub/models--<pemilik>--<model>/snapshots/<revisi>/`. Folder EmbeddingGemma harus berisi `config.json` dengan `model_type: embedding_gemma2` serta bobot `model.safetensors` atau indeks bobotnya. Folder Whisper harus berisi `config.json` dan `weights.npz` atau `weights.safetensors`.

Model yang terdeteksi belum menjamin runtime dapat menjalankannya: paket Python dan arsitektur model juga harus cocok. Detail pemeriksaan lokasi ada di [ModelDiscovery.swift](Sources/CarfoCore/ModelDiscovery.swift), dan implementasi inferensi ada di [worker.py](Sources/Carfo/Resources/Engine/worker.py).

## Cara pengindeksan bekerja

Video dan audio dibagi menjadi segmen hingga 12 detik. Untuk video, Carfo mengambil tiga frame per segmen dan mengolahnya bersama melalui encoder visual. Audio disiapkan sebagai WAV mono 16 kHz PCM16. File gambar diolah langsung sebagai masukan visual.

EmbeddingGemma 2 menghasilkan embedding 768 dimensi yang dinormalisasi, lalu dibandingkan dengan kueri menggunakan cosine similarity. Mode Video, Gambar, dan Suara menampilkan segmen terbaik per file. Preview video/audio diarahkan ke posisi segmen tersebut; membuka file di aplikasi lain tetap membuka file asli.

Jika Whisper tersedia, Carfo membuat transkrip bertimestamp dan embedding teks untuk pencarian dialog. Mode Dialog dapat menampilkan beberapa kutipan dari file yang sama, lengkap dengan konteks sebelum dan sesudahnya. Pemindaian video juga membaca subtitle `.srt` atau `.vtt` dengan nama dasar yang sama, misalnya `wawancara.mp4` dan `wawancara.srt`.

### Data di Mac

Secara default, Carfo menyimpan data aplikasinya di:

```text
~/Library/Application Support/Carfo/
├── library.json    # Folder, metadata, embedding, transkrip, dan progres indeks
├── Thumbnails/     # Thumbnail gambar dan video
├── engine.log      # Log mesin lokal
└── Working/        # Area kerja untuk potongan media sementara
```

File media asli tetap berada di folder Anda. Aplikasi tidak memindahkan atau mengubahnya. Mesin Python berkomunikasi dengan aplikasi melalui stdin/stdout dan berjalan dengan mode offline Hugging Face serta Transformers.

## Build dari source

Proyek memakai Swift Package Manager tanpa dependency Swift eksternal. Jalankan perintah dari direktori utama repositori.

### Persiapan paket

[Skrip build](scripts/build-app.sh) menyalin runtime dan model lokal ke bundle aplikasi. Sebelum membuat paket lengkap:

1. Siapkan runtime Python beserta paket inferensinya di `scratch/test-python/`. Skrip menyalin isi direktori ini ke `Contents/Resources/Python/`.
2. Siapkan folder model EmbeddingGemma 2 dan, untuk transkripsi, Whisper MLX.
3. Sesuaikan variabel `MODEL_SRC` dan `WHISPER_SRC` di `scripts/build-app.sh` dengan lokasi model Anda. Nilai saat ini menunjuk cache dan revisi model di Mac pembuat.

Skrip hanya menyalin komponen yang direktori sumbernya tersedia. Build aplikasi dapat berhasil tanpa menyertakan model atau Python, sehingga ketersediaan pencarian semantik perlu diperiksa terpisah dari keberhasilan kompilasi.

### Kompilasi

```sh
zsh scripts/build-app.sh
```

Hasil build berada di `build/Carfo.app`. Buka melalui Finder, lalu ikuti langkah penggunaan di atas.

Skrip saat ini memakai tanda tangan ad hoc (`codesign --sign -`). Proses build belum mencakup penandatanganan Developer ID, notarization, atau pembuatan DMG.

### Pengujian

```sh
swift test \
  --cache-path .build/Cache \
  --config-path .build/Configuration \
  --security-path .build/Security \
  --disable-sandbox
```

Pengujian mencakup pembagian segmen, validasi vektor, pencarian semantik dan nama file, transkrip, subtitle, penyimpanan indeks, serta komunikasi dengan worker. Pengujian integrasi AVFoundation memakai fixture `.runtime/Fixtures/Videos/Test red.mp4` dan dilewati bila fixture tidak tersedia atau decoder tidak dapat diakses oleh lingkungan pengujian.

Untuk menyiapkan aplikasi validasi native setelah build:

```sh
python3 scripts/prepare-validation.py
```

Skrip ini memerlukan FFmpeg untuk membuat media sintetis; FFmpeg tidak diperlukan untuk penggunaan aplikasi sehari-hari. Buka `.runtime/Carfo Check.app` melalui Finder. Hasil validasi ditulis ke `.runtime/NativeValidation/self-test.json`. Fixture validasi ini terpisah dari fixture pengujian integrasi Swift di atas.

## Struktur proyek

```text
Sources/
├── Carfo/                  # Aplikasi SwiftUI/AppKit, pencarian, dan pengaturan
│   └── Resources/Engine/    # Worker Python untuk MLX dan Whisper
└── CarfoCore/              # Koleksi, pemrosesan media, model lokal, dan pencarian
Tests/CarfoCoreTests/        # Unit test dan pengujian integrasi media
scripts/                    # Build bundle dan persiapan validasi native
Support/                    # Info.plist dan ikon aplikasi
Assets/                     # Aset visual Carfo
Validation/                 # Hasil validasi model lokal
Package.swift               # Konfigurasi Swift Package Manager
```

## Batasan dan pemecahan masalah

| Kondisi | Penjelasan atau langkah berikutnya |
| --- | --- |
| Hanya nama file yang cocok | Tunggu indeks selesai dan pastikan model serta runtime tersedia. Jika inferensi gagal, lihat pesan aplikasi dan `engine.log`. |
| Dialog belum memiliki kutipan | Siapkan Whisper beserta `mlx-whisper`, atau subtitle pendamping untuk video. Tanpa transkrip, mode Dialog memakai pendekatan embedding audio bila tersedia. |
| Folder atau file tidak dapat dibuka | Pilih ulang folder untuk memperbarui akses. Jalankan Pindai ulang setelah perubahan isi folder. |
| File gagal dibaca atau diindeks | Dukungan bergantung pada decoder macOS, Pillow, dan format yang diterima model; ekstensi yang dikenali tidak menjamin semua codec dapat diproses. |
| Adegan singkat terlewat | Sampling tiga frame dapat melewatkan kejadian singkat. Timestamp visual menunjukkan segmen, bukan batas adegan yang presisi. |

Hasil semantik menunjukkan kedekatan isi dengan kueri, bukan persentase kepastian. Kualitas transkrip dan posisi waktunya bergantung pada audio serta model. Windows, Linux, dan Mac Intel belum menjadi target aplikasi ini.

## Kontribusi

Untuk laporan masalah, sertakan versi macOS, jenis chip Mac, langkah reproduksi, dan pesan error yang muncul. Jika masalah terkait media tertentu, sertakan format file serta contoh yang boleh dibagikan. Periksa log sebelum melampirkannya karena log dapat memuat lokasi file lokal.

Untuk perubahan kode, jelaskan perilaku yang diperbaiki dan pengujian yang dijalankan dalam pull request.

## Lisensi

Repositori ini belum menyertakan file `LICENSE`. Model, runtime Python, dan dependency pihak ketiga memiliki ketentuan lisensi masing-masing.
