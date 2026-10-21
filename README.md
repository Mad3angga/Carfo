# Carfo

Cari video, gambar, dan audio di Mac berdasarkan isi medianya.

Carfo adalah aplikasi menu bar macOS untuk menemukan footage dari deskripsi adegan, kutipan percakapan, atau bunyi yang Anda ingat. Buka panel pencarian, ketik kueri, lalu tinjau hasil dan posisi waktunya sebelum membuka file asli.

Carfo memproses media secara lokal di Mac dan dapat digunakan secara offline. Komponen pemrosesan sudah disertakan dalam aplikasi, sehingga Anda cukup menginstal aplikasi dan menambahkan folder koleksi.

Repositori ini digunakan untuk membagikan aplikasi Carfo dalam format DMG. Source code tidak disertakan.

## Mode pencarian

| Mode | Media yang dicari | Contoh kueri |
| --- | --- | --- |
| Video | Isi visual dan audio dalam video | `orang berjalan di pantai` |
| Gambar | Isi file gambar | `mobil merah di jalan` |
| Dialog | Ucapan dalam video atau audio, dengan kutipan dan timestamp jika transkrip tersedia | `kita mulai syuting besok` |
| Suara | Bunyi dalam file audio dan video yang memiliki trek audio | `suara hujan dan petir` |

<img width="2880" height="1870" alt="image" src="https://github.com/user-attachments/assets/10b0d80a-b235-489c-9c67-42e311b935a6" />
<img width="2880" height="1870" alt="image" src="https://github.com/user-attachments/assets/9c36a637-381f-457a-9e9c-e4a3b0b31290" />
<img width="1800" height="1048" alt="image" src="https://github.com/user-attachments/assets/8dcd8992-8e05-4f80-8cc8-3bc0c009af0e" />
<img width="2880" height="1870" alt="image" src="https://github.com/user-attachments/assets/d9d1de20-8ed2-4a03-bee2-1e3c3da5164a" />
Kueri di atas adalah contoh penggunaan. Hasil bergantung pada isi koleksi dan progres pengindeksan media Anda.

## Fitur

- Panel pencarian mengambang dengan pintasan global `⌥Spasi`.
- Koleksi dari beberapa folder beserta subfoldernya, dengan filter pencarian per folder.
- Pencarian nama file setelah pemindaian, termasuk saat pengindeksan isi media belum selesai.
- Pencarian dialog berdasarkan kata atau kemiripan makna, dengan konteks percakapan di sekitar kutipan.
- Preview video dan audio pada segmen yang ditemukan, akses ke Finder, serta seret file ke aplikasi lain.
- Pengindeksan bertahap yang menyimpan progres dan dapat dilanjutkan setelah dihentikan.
- Tema terang, gelap, atau mengikuti sistem, serta pilihan membuka aplikasi saat login.

## Persyaratan

- Mac dengan Apple Silicon dan macOS 14 atau lebih baru.
- Ruang penyimpanan untuk aplikasi, indeks koleksi, dan thumbnail. Kebutuhannya bergantung pada ukuran koleksi media.

Anda tidak perlu menginstal Python, menyiapkan API key, atau menjalankan server.

## Unduh dan instal

1. Unduh file `.dmg` Carfo yang tersedia di halaman GitHub ini.
2. Buka file `.dmg` tersebut melalui Finder.
3. Seret `Carfo.app` ke folder Applications.
4. Setelah penyalinan selesai, keluarkan disk image Carfo dari Finder.
5. Buka Carfo dari folder Applications. Ikon Carfo akan muncul di menu bar.

## Cara penggunaan

1. Klik ikon Carfo di menu bar dan buka Pengaturan. Saat Carfo aktif, Anda juga dapat memakai `⌘,`.
2. Klik **Tambah folder** dan pilih folder media. Carfo akan memindai dan mengindeks koleksi tersebut.
3. Tunggu pengindeksan selesai untuk mencari berdasarkan isi media. File yang sudah dipindai tetap dapat dicari berdasarkan namanya selama proses berjalan.
4. Tekan `⌥Spasi`, pilih mode pencarian, lalu ketik kueri.
5. Pilih hasil untuk meninjau preview. Tekan `Return` untuk membuka file asli atau `⌘Return` untuk menampilkannya di Finder.

Gunakan **Pindai ulang** di Pengaturan setelah menambah, mengubah, atau menghapus media di folder koleksi. Tombol ini juga melanjutkan pengindeksan file yang belum selesai. Anda dapat menghentikan pengindeksan; progres yang sudah tersimpan tetap tersedia.

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

## Privasi dan penyimpanan

Pemrosesan media dan pencarian berjalan secara lokal. File media Anda tidak dikirim ke server.

Indeks, transkrip, thumbnail, dan log disimpan di `~/Library/Application Support/Carfo/`. File asli tetap berada di folder Anda dan tidak dipindahkan atau diubah. Mengeluarkan folder dari koleksi Carfo tidak menghapus file aslinya.
