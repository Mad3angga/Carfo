# Checklist perbaikan Carfo

Tanggal audit: 22 Oktober 2026.

Daftar ini berasal dari audit kode dan pengujian lokal pada kondisi working tree saat audit, termasuk perubahan yang belum di-commit. Status diperbarui setelah implementasi dan verifikasi lokal untuk kandidat Carfo 2.0. Checkbox kosong tetap menandakan kriteria yang belum seluruhnya terpenuhi.

## Pembaruan implementasi 2.0

| Item | Status dan bukti |
| --- | --- |
| CF-10 | Selesai: startup metadata dan indeks di background, status loading, proteksi simpan sebelum load selesai, catatan tahap startup. UI uji muncul sekitar 193 ms; metadata 288 ms dan indeks 292 ms untuk koleksi kosong. Model dingin 4,68 detik, hangat 199 ms, setelah idle paksa 4,03 detik. Idle produksi 300 detik; evaluasi energi jangka panjang tetap diperlukan. |
| CF-11 | Selesai: statistik delta per clip, pemetaan ID selama batch scan/indexing, hitungan folder tersimpan. Uji penambahan/penghapusan, indexing parsial, dan perubahan status lulus. Delta statistik pada 1.000 video sekitar 0,00125 ms. |
| CF-12 | Selesai: generator per file, API batch asinkron, validasi actual timestamp dalam 100 ms, pembatalan dan pembersihan request. Enam fixture H.264/HEVC/ProRes pada 360p/1080p berhasil. Median batch 31–67 ms versus generator per frame 68–216 ms; RSS proses benchmark sekitar 29,2 MiB. |
| CF-13 | Selesai: WAV streaming, batas durasi sebelum ekstraksi, potongan 60 detik dengan overlap dua detik, offset dan asal transkrip tersimpan. Uji kegagalan potongan kedua dilanjutkan dari 60 detik tanpa mengulang potongan pertama. Audio sintetis 20 menit menghasilkan WAV 38,4 MB dengan RSS puncak proses ekstraksi sekitar 27,2 MiB. Kualitas batas ucapan nyata masih memerlukan koleksi berlabel. |
| CF-14 | Selesai: asal transkrip/fingerprint sidecar persisten, perubahan subtitle tanpa perubahan video terdeteksi, cue tersedia hanya di-embed termasuk tanpa Whisper. Uji SRT, VTT settings, identifier, teks angka, timestamp invalid, dan subtitle invalid lulus. |
| CF-15 | Sebagian: bobot nama file, prioritas nama persis, dan penolakan skor negatif/rendah diterapkan. **Tetap terbuka atas keputusan pengguna:** belum ada koleksi media berlabel untuk kalibrasi dan pengukuran retrieval representatif. |
| CF-16 | Selesai: pemuatan/decoding thumbnail di background; key memuat versi file, ukuran, dan modification time thumbnail. Uji async, ukuran kecil/besar, serta perubahan isi pada URL sama lulus. |
| CF-17 | Selesai untuk build lokal: path input eksplisit, Python/dependency lock 83 distribusi, pemeriksaan komponen wajib, hash model dan kontrak preprocessing, Python isolated mode. Bundle dengan runtime terpisah lolos smoke test offline seluruh mode memakai cache kosong. Sumber CPython standalone tetap input eksternal terdokumentasi di BUILDING.md. |
| CF-18 | Alur signing/notarization/stapling dan verifikasi artefak tersedia. **Masih terbuka:** nol identitas signing valid pada mesin ini; Developer ID, notarization produksi, dan instalasi Mac bersih belum bisa dibuktikan. Build lokal memakai signature ad hoc. |
| CF-19 | Selesai secara lokal: dependency injection direktori/defaults/instalasi/worker, regresi CF-01–CF-08 dan workflow AppModel, fixture tanpa path pribadi, CI strict concurrency dengan warnings-as-errors dan actor data race checks. Eksekusi CI remote belum dilakukan. |
| CF-20 | Sebagian: baseline indeks, inferensi dingin/hangat/setelah idle, pembatalan, codec, audio streaming, dan tahap startup disimpan. **Masih terbuka:** throughput indexing penuh, profil main thread Instruments, RAM worker selama indexing panjang, kualitas retrieval representatif, serta batas rilis untuk metrik tersebut. |

Rincian: [CHANGELOG.md](CHANGELOG.md), [BUILDING.md](BUILDING.md), [Validation/README.md](Validation/README.md). Angka adalah pengukuran lokal, bukan jaminan performa perangkat lain. Minimum bundle dikoreksi menjadi macOS 26.2 berdasarkan deployment target biner MLX bawaan.

Prioritas:

- **P0:** perlindungan indeks yang harus diselesaikan sebelum rilis berikutnya.
- **P1:** ketepatan hasil, kelengkapan pengindeksan, keamanan concurrency, dan respons pencarian.
- **P2:** kapasitas koleksi, efisiensi pemrosesan, pengujian, dan distribusi.

## P0: Perlindungan indeks

- [x] **CF-01: Cegah penimpaan indeks ketika pemuatan gagal.**

  Masalah: setelah `store.load()` gagal, aplikasi memakai library kosong, membersihkan thumbnail, lalu dapat menimpa indeks lama saat menyimpan atau keluar. Skenario ini terkonfirmasi pada direktori uji.

  Tindakan: simpan status kegagalan pemuatan; hentikan penyimpanan otomatis dan pembersihan thumbnail selama status tersebut aktif. Pertahankan berkas asli, sediakan backup valid, dan buat alur pemulihan atau pembangunan ulang indeks.

  Kriteria selesai: uji startup, penyimpanan, dan shutdown dengan JSON rusak serta versi indeks yang tidak didukung. Berkas awal dan thumbnail tetap utuh sampai tindakan pemulihan dipilih.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [Library.swift](Sources/CarfoCore/Library.swift), fungsi `init`, `flushSaves`, `shutdown`, dan `pruneThumbnails`.

## P1: Keandalan dan respons pencarian

- [x] **CF-02: Perbaiki status selesai untuk audio yang baru terindeks sebagian.**

  Masalah: `isIndexed` untuk audio memakai `segments.contains`. Satu segmen selesai dapat membuat seluruh file dianggap selesai dan dilewati saat melanjutkan indexing.

  Tindakan: syaratkan seluruh segmen audio yang diperlukan sudah memiliki embedding. Samakan definisi selesai pada pemilihan kandidat, statistik, dan progress bar.

  Kriteria selesai: hentikan indexing setelah satu dari beberapa segmen selesai; proses berikutnya melanjutkan segmen yang tersisa tanpa mengulang segmen selesai. File baru berstatus selesai setelah seluruh segmen lengkap.

  Rujukan: [Library.swift](Sources/CarfoCore/Library.swift), [AppModel.swift](Sources/Carfo/AppModel.swift), properti `isIndexed`, fungsi `needsIndexing` dan `indexUnits`.

- [x] **CF-03: Bedakan kegagalan transkripsi dari transkripsi yang berhasil tanpa ucapan.**

  Masalah: blok penanganan error mengisi `transcribedAt`, sehingga file tanpa cue dapat dianggap selesai. Keberhasilan embedding berikutnya juga dapat menghapus error transkripsi.

  Tindakan: pisahkan status dan error setiap tahap. Isi status berhasil hanya setelah transkripsi selesai; pertahankan status gagal agar proses dapat dicoba ulang.

  Kriteria selesai: kegagalan Whisper sementara tetap terlihat, tidak menambah jumlah transkripsi selesai, dan dapat dilanjutkan. Audio yang berhasil diproses tanpa ucapan tetap dianggap selesai.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [Library.swift](Sources/CarfoCore/Library.swift), tahap transkripsi dalam `startIndexing` dan properti `needsTranscript`.

- [x] **CF-04: Hilangkan mutasi Array bersama pada pencarian paralel.**

  Masalah: `concurrentPerform` menulis ke variabel `parallelResults` bersama. Pemeriksaan strict concurrency memperingatkan mutasi captured variable dan capture closure yang belum `Sendable`.

  Tindakan: kembalikan hasil per kelompok pekerjaan dan gabungkan melalui satu pemilik data. Tentukan batas paralelisme berdasarkan benchmark.

  Kriteria selesai: diagnostik concurrency pada jalur ini terselesaikan; hasil pencarian konsisten untuk sedikitnya 24 kandidat, termasuk beberapa pencarian bersamaan. Jalankan Thread Sanitizer pada lingkungan yang mendukungnya.

  Rujukan: [Search.swift](Sources/CarfoCore/Search.swift), cabang `candidates.count >= 24`.

- [x] **CF-05: Perbaiki pencarian dialog ketika seluruh file belum ditranskrip.**

  Masalah: `AppModel` mengirim `textEmbedding`, tetapi jalur audio cadangan saat seluruh kandidat belum ditranskrip memakai `embedding`. Pengujian tambahan mereproduksi hasil semantik yang kosong.

  Tindakan: konsistenkan pemilihan vektor kueri pada semua cabang pencarian dialog.

  Kriteria selesai: pencarian menemukan segmen audio yang sesuai pada koleksi tanpa transkrip, koleksi campuran, dan koleksi yang sudah ditranskrip. Uji menggunakan parameter yang sama dengan panggilan dari `AppModel`.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [Search.swift](Sources/CarfoCore/Search.swift), fungsi `scheduleSearch` dan cabang mode dialog.

- [x] **CF-06: Gunakan identitas model yang stabil untuk kompatibilitas embedding.**

  Masalah: kompatibilitas menggunakan nama folder terakhir, yang pada aplikasi terpaket dapat selalu bernama `Model`. Invalidasi saat mismatch juga belum menghapus embedding cue transkrip.

  Tindakan: sertakan identitas dan revisi model dalam manifest build; catat versi prompt serta preprocessing. Invalidasi seluruh embedding yang terdampak, sambil mempertahankan teks transkrip.

  Kriteria selesai: dua revisi model dalam folder bernama sama terdeteksi berbeda. Embedding segmen, cue, dan cache kueri tidak tercampur antarversi. Penanganan indeks lama tanpa identitas model ditentukan secara eksplisit.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [Library.swift](Sources/CarfoCore/Library.swift), properti `indexMatchesModel` dan `modelRevision`.

- [x] **CF-07: Tampilkan hasil teks sebelum menunggu model.**

  Masalah: hasil nama file menunggu inferensi, sementara worker yang sama dapat sedang mengerjakan embedding media atau transkripsi.

  Tindakan: tampilkan hasil nama file dan pencarian teks terlebih dahulu, kemudian perbarui dengan hasil semantik. Beri pekerjaan interaktif kesempatan berjalan di antara unit indexing yang pendek.

  Kriteria selesai: pencarian teks tetap merespons ketika worker sibuk. Hasil kueri lama tidak menggantikan kueri terbaru. Ukur latensi hasil pertama saat idle dan saat indexing.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [LocalEngine.swift](Sources/CarfoCore/LocalEngine.swift), fungsi `scheduleSearch` dan antrean permintaan model.

- [x] **CF-08: Buat pembatalan worker dapat merespons pekerjaan yang sedang berjalan.**

  Masalah: polling sinkron dalam actor menahan layanan permintaan berikutnya, termasuk `stop()`. Pada worker uji dengan pekerjaan dua detik, pembatalan masih menunggu sekitar 1,88 detik.

  Tindakan: gunakan pembacaan respons tanpa memblokir actor, identitas permintaan, serta aturan pembatalan yang menjaga sinkronisasi protokol. Pecah transkripsi panjang menjadi unit yang dapat dihentikan.

  Kriteria selesai: uji pembatalan, timeout, worker berhenti mendadak, dan pencarian baru setelah pembatalan. Respons lama tidak terbaca sebagai hasil permintaan baru; waktu respons tombol hentikan tercatat.

  Rujukan: [LocalEngine.swift](Sources/CarfoCore/LocalEngine.swift), [worker.py](Sources/Carfo/Resources/Engine/worker.py), fungsi `request`, `stop`, dan loop protokol.

- [x] **CF-09: Ganti penyimpanan seluruh library dengan pembaruan incremental.**

  Masalah: setiap simpan melakukan encoding dan penulisan ulang seluruh JSON. Benchmark 1.000 video menghasilkan JSON 181,9 MiB dan waktu simpan sekitar 4,25 detik.

  Tindakan: simpan metadata, status pekerjaan, segmen, dan cue sebagai record yang dapat diperbarui secara terpisah, misalnya menggunakan SQLite. Simpan embedding dalam format biner. Siapkan migrasi dari JSON dengan backup dan pemeriksaan integritas. Sebelum migrasi selesai, batasi antrean snapshot dan gabungkan perubahan yang belum ditulis.

  Kriteria selesai: perubahan satu segmen tidak menulis ulang seluruh koleksi. Migrasi mempertahankan folder, bookmark, ID, embedding, transkrip, dan progres parsial. Uji interupsi migrasi, kegagalan penulisan, serta pemulihan backup.

  Rujukan: [Library.swift](Sources/CarfoCore/Library.swift), [AppModel.swift](Sources/Carfo/AppModel.swift), fungsi `load`, `save`, `persist`, dan `persistSoon`.

## P2: Efisiensi, kualitas hasil, dan distribusi

- [x] **CF-10: Muat indeks secara bertahap dan evaluasi kebijakan pelepasan model.**

  Masalah: startup membaca indeks pada main actor. Worker dilepas setelah idle 45 detik, sedangkan waktu muat model yang terukur sekitar 10,48 detik.

  Tindakan: tampilkan antarmuka sebelum seluruh indeks selesai dimuat; prioritaskan metadata yang diperlukan untuk pencarian teks. Evaluasi waktu idle model berdasarkan latensi dan penggunaan memori, serta pastikan jalur error tetap membersihkan resource.

  Kriteria selesai: ukur waktu antarmuka siap, indeks siap, model siap, dan pencarian setelah idle. Antarmuka menunjukkan tahap yang sedang berjalan dan tetap dapat menerima interaksi.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [LocalEngine.swift](Sources/CarfoCore/LocalEngine.swift), inisialisasi library dan `resetIdleTimer`.

- [x] **CF-11: Kurangi penghitungan ulang seluruh koleksi pada setiap pembaruan.**

  Masalah: perubahan satu embedding menghitung ulang seluruh `LibraryStats`; batch scan membangun ulang dictionary posisi; tampilan folder memfilter seluruh koleksi untuk menghitung jumlah file.

  Tindakan: perbarui statistik berdasarkan perubahan clip, gunakan pemetaan ID yang dipertahankan selama pekerjaan, dan gabungkan pembaruan UI. Pisahkan state progress indexing dari state pencarian bila diperlukan.

  Kriteria selesai: perubahan satu segmen tidak memindai seluruh koleksi untuk statistik. Jumlah file dan status tetap benar setelah scan, hapus folder, indexing, serta pembatalan. Profilkan main thread selama proses tersebut.

  Rujukan: [AppModel.swift](Sources/Carfo/AppModel.swift), [SettingsView.swift](Sources/Carfo/SettingsView.swift), observer `library`, `mergeScannedClips`, dan penghitungan file per folder.

- [x] **CF-12: Gunakan kembali decoder dan ambil frame secara asinkron berkelompok.**

  Masalah: setiap frame membuat asset dan image generator baru serta memakai API sinkron yang deprecated pada macOS 15.

  Tindakan: gunakan kembali asset dan generator per file, ambil beberapa waktu sampel melalui API asinkron, serta tetapkan toleransi waktu yang sesuai. Periksa waktu frame aktual agar timestamp indeks tetap dapat dipercaya.

  Kriteria selesai: bandingkan waktu ekstraksi dan penggunaan memori sebelum/sesudah pada beberapa codec dan resolusi. Sampel tetap berada dalam toleransi segmen yang ditentukan; pembatalan menghentikan permintaan yang tersisa.

  Rujukan: [MediaProcessor.swift](Sources/CarfoCore/MediaProcessor.swift), fungsi `frame` dan `frames`.

- [x] **CF-13: Tulis audio secara streaming dan transkripsikan per potongan.**

  Masalah: Swift menampung seluruh PCM dan membentuk buffer WAV tambahan. Worker baru memeriksa batas empat jam setelah WAV disiapkan.

  Tindakan: tulis PCM langsung ke file, periksa batas durasi sebelum ekstraksi penuh, dan transkripsikan per potongan dengan overlap serta penyesuaian timestamp. Simpan progres tiap potongan.

  Kriteria selesai: ukur RAM puncak pada audio panjang. Pembatalan dan pelanjutan tidak mengulang seluruh transkripsi. Cue di batas potongan tidak hilang atau terduplikasi; berkas sementara dibersihkan setelah berhasil maupun gagal.

  Rujukan: [MediaProcessor.swift](Sources/CarfoCore/MediaProcessor.swift), [AppModel.swift](Sources/Carfo/AppModel.swift), [worker.py](Sources/Carfo/Resources/Engine/worker.py), ekstraksi `full_audio.wav` dan `Transcriber.transcribe`.

- [x] **CF-14: Pertahankan subtitle yang tersedia dan perbaiki parser VTT.**

  Masalah: indexing dapat mengganti subtitle dengan hasil Whisper, perubahan subtitle tidak terdeteksi jika video tetap sama, dan parser menolak contoh VTT dengan pengaturan cue setelah timestamp.

  Tindakan: simpan asal transkrip dan fingerprint subtitle, buat embedding dari cue yang sudah tersedia, dan tangani pengaturan cue VTT tanpa mencampurkannya dengan timestamp.

  Kriteria selesai: perubahan SRT/VTT terdeteksi tanpa mengubah video. Subtitle valid tidak ditimpa otomatis. Uji SRT, VTT dengan pengaturan cue, cue identifier, dan file subtitle tidak valid.

  Rujukan: [MediaProcessor.swift](Sources/CarfoCore/MediaProcessor.swift), [AppModel.swift](Sources/Carfo/AppModel.swift), cache `scanFile`, `SubtitleParser`, dan tahap transkripsi.

- [ ] **CF-15: Kalibrasi ranking gabungan dan penolakan hasil tidak relevan.**

  Masalah: kecocokan nama file belum menambah bobot ketika hasil embedding tersedia; kemiripan negatif masih dapat dikembalikan. Bobot visual-audio dan ambang dialog belum memiliki benchmark representatif dalam repositori.

  Tindakan: gabungkan sinyal nama file, teks, dan embedding berdasarkan mode. Kalibrasi bobot dan ambang menggunakan kueri berlabel, termasuk kueri yang tidak memiliki kecocokan.

  Kriteria selesai: ukur Recall@5, ketepatan hasil teratas, dan kesalahan timestamp. Cakup bahasa Indonesia, bahasa Inggris, ucapan bising, bunyi lingkungan, adegan singkat, serta nama file yang cocok persis.

  Rujukan: [Search.swift](Sources/CarfoCore/Search.swift), fungsi `search` dan `dialogueMatches`.

- [x] **CF-16: Perbaiki invalidasi dan pemuatan cache thumbnail.**

  Masalah: cache hanya memakai URL sehingga dapat mempertahankan gambar lama setelah file berubah atau memakai ukuran yang tidak sesuai. Pembacaan dan decoding saat cache miss masih sinkron dari view.

  Tindakan: sertakan identitas versi file dan ukuran tujuan pada cache key, invalidasi saat thumbnail berubah, dan pindahkan pemuatan yang berat dari main thread.

  Kriteria selesai: preview berubah setelah file atau thumbnail diperbarui, ukuran thumbnail tidak membatasi kualitas preview besar, dan navigasi hasil tetap responsif saat cache kosong.

  Rujukan: [SearchView.swift](Sources/Carfo/SearchView.swift), `ThumbnailCache`, `clipThumbnailImage`, dan `imagePreviewView`.

- [x] **CF-17: Buat packaging runtime yang dapat direproduksi.**

  Masalah: skrip memakai path model pribadi, menyalin runtime dari `scratch/test-python`, dan dapat melewati komponen wajib yang tidak ditemukan. Runtime saat audit sekitar 1,5 GB dengan 256 distribusi paket.

  Tindakan: catat versi dependensi Python, parameterkan sumber model dan runtime, serta gagalkan build jika komponen wajib tidak tersedia. Telusuri dependensi sebelum merampingkan paket.

  Kriteria selesai: build dari checkout bersih dapat menghasilkan bundle lengkap. Semua mode pencarian dan transkripsi berjalan offline menggunakan runtime bawaan, tanpa bergantung pada Python atau cache model di mesin pembuat.

  Rujukan: [build-app.sh](scripts/build-app.sh), [ModelDiscovery.swift](Sources/CarfoCore/ModelDiscovery.swift).

- [ ] **CF-18: Lengkapi signing dan validasi artefak distribusi.**

  Masalah: aplikasi yang diperiksa memakai signature ad hoc tanpa Team Identifier. Pemeriksaan DMG dalam skrip berfokus pada keberadaan aplikasi dan symlink Applications.

  Tindakan: tambahkan Developer ID signing, hardened runtime, notarization, stapling, dan verifikasi bundle final. Uji pemasangan pada mesin bersih sesuai versi macOS minimum yang didukung.

  Kriteria selesai: pemeriksaan signature dan notarization lulus; aplikasi hasil pemasangan menjalankan model, mengakses folder, dan memproses media menggunakan resource di dalam bundle.

  Rujukan: [build-app.sh](scripts/build-app.sh), [build-dmg.sh](scripts/build-dmg.sh), [Info.plist](Support/Info.plist).

- [x] **CF-19: Tambahkan pengujian workflow aplikasi dan pemeriksaan concurrency di CI.**

  Masalah: 26 pengujian yang ada lulus, tetapi belum menangkap beberapa kegagalan pada siklus `AppModel`, pembatalan, dan jalur pencarian paralel.

  Tindakan: sediakan dependency injection secukupnya untuk worker dan penyimpanan agar kegagalan dapat diuji secara deterministik. Tambahkan pengujian regresi CF-01 sampai CF-08 dan jalankan pemeriksaan strict concurrency dalam CI.

  Kriteria selesai: pengujian mencakup indeks rusak, audio parsial, Whisper gagal sementara, pergantian model, worker timeout, respons terlambat, dan pencarian saat indexing. Pengujian tidak membutuhkan path media pribadi.

  Rujukan: [CarfoCoreTests.swift](Tests/CarfoCoreTests/CarfoCoreTests.swift), [MediaIntegrationTests.swift](Tests/CarfoCoreTests/MediaIntegrationTests.swift), [Package.swift](Package.swift).

- [ ] **CF-20: Simpan benchmark performa dan kualitas sebagai acuan regresi.**

  Tindakan: catat latensi hasil teks pertama, pencarian hangat/dingin, pembatalan, startup, penulisan indeks, RAM puncak, dan throughput indexing. Gunakan koleksi sintetis untuk pengukuran berulang serta media berlabel untuk kualitas retrieval. Catat perangkat, versi build, ukuran koleksi, dan kondisi cache.

  Kriteria selesai: hasil dapat diulang, terpisah antara inferensi dan pencarian indeks, serta memiliki batas regresi yang disepakati. Optimasi berikutnya dibandingkan dengan baseline yang sama.

  Rujukan: [local-model.json](Validation/local-model.json), [prepare-validation.py](scripts/prepare-validation.py). Validasi merah/biru yang tersedia merupakan pemeriksaan fungsi, belum menjadi benchmark kualitas retrieval.

## Urutan pengerjaan

1. Selesaikan CF-01 untuk menjaga indeks yang gagal dibaca.
2. Perbaiki CF-02 sampai CF-06 dan tambahkan pengujian regresinya melalui CF-19.
3. Kerjakan respons pencarian dan pembatalan pada CF-07 serta CF-08.
4. Migrasikan penyimpanan melalui CF-09; lanjutkan pemuatan bertahap dan pembaruan UI pada CF-10 serta CF-11.
5. Optimalkan pipeline media dan subtitle melalui CF-12 sampai CF-14, lalu evaluasi ranking dan cache melalui CF-15 serta CF-16.
6. Lengkapi packaging dan distribusi melalui CF-17 serta CF-18. Mulai pencatatan benchmark CF-20 sebelum perubahan performa agar hasilnya dapat dibandingkan.

## Baseline audit

Benchmark core memakai kompilasi dengan optimasi, vektor 768 dimensi, 10 segmen per video, dan embedding visual serta audio. Waktu pencarian merupakan median tujuh pengukuran dan tidak mencakup inferensi model. Koleksi sintetis ini tidak menyertakan transkrip.

| Video | Segmen | JSON | Simpan | Baca | Pencarian |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 1.000 | 18,2 MiB | 431 ms | 326 ms | 1,0 ms |
| 500 | 5.000 | 91,0 MiB | 2.114 ms | 1.663 ms | 6,9 ms |
| 1.000 | 10.000 | 181,9 MiB | 4.253 ms | 3.297 ms | 15,1 ms |

Pengukuran tambahan pada mesin audit:

- Worker dan model mulai siap setelah sekitar 10,48 detik.
- Embedding teks pendek setelah model siap memerlukan sekitar 126 sampai 241 ms.
- Tiga teks dalam batch memerlukan sekitar 196 ms, dibanding sekitar 356 ms jika diproses satu per satu.
- Artefak aplikasi sekitar 3,4 GB dan DMG sekitar 1,9 GB.
- Seluruh 26 pengujian proyek lulus saat audit.
- Thread Sanitizer berhenti tanpa menghasilkan laporan. Temuan concurrency didukung diagnostik compiler dan pemeriksaan kode; crash aplikasi akibat jalur tersebut belum direproduksi.

Angka di atas adalah hasil pengukuran lokal, bukan target performa untuk semua Mac. Profiling antarmuka dengan Instruments, penggunaan energi jangka panjang, dan benchmark retrieval pada koleksi nyata masih perlu dilakukan.
