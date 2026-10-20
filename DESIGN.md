# Arah desain Carfo

Sumber: rancangan Pencil pengguna, empat frame `Spotlight · Hasil pencarian footage`, `Spotlight · Mulai mencari`, `Spotlight · Kondisi pencarian`, dan `Carfo · Akses menu bar`.

- Jenis: utilitas menu bar macOS untuk mencari koleksi footage lokal.
- Bahasa visual: Spotlight macOS, panel pencarian dan panel hasil terpisah, kaca buram, sudut 14 pt, bayangan terbatas pada panel melayang.
- Komposisi: pencarian sebagai fokus utama; daftar rapat di kiri dan preview besar di kanan membantu mengenali klip.
- Tipografi: Inter jika sudah terpasang, font sistem macOS sebagai fallback native yang tidak memerlukan unduhan.
- Palet: permukaan netral terang atau gelap, teks utama native, teks sekunder `#5E6572`/`#B8C1CE`, aksen `#075AB8`/`#79B8FF`, aksi `#0866D8`/`#1669CC`.
- ENERGY 1 / RHYTHM 1 / MOTION 1: tenang, struktur daftar konsisten, animasi terbatas pada perubahan ukuran panel dan menghormati Reduce Motion.

Alasan keputusan:

| Keputusan | Tujuan |
| --- | --- |
| Panel melayang terpisah dari aplikasi utama | Pengguna dapat mencari sambil bekerja di aplikasi editing |
| Material native dengan lapisan permukaan hampir opak | Mempertahankan konteks desktop sambil menjaga kontras teks |
| Satu warna pilihan aktif | Menunjukkan posisi navigasi keyboard |
| Preview di samping daftar | Mengurangi kebutuhan membuka banyak file untuk mengenali footage |
| Ukuran awal lebih kecil | Tampilan awal hanya memuat panduan dan status koleksi |
| Simbol sistem untuk folder, video, keyboard, dan suara | Mengikuti fungsi serta bahasa antarmuka macOS pada rancangan |
| Pengaturan native dalam satu jendela | Menyediakan folder footage, tema, dan shortcut yang berfungsi |

Seluruh hasil, thumbnail, durasi, resolusi, dan jumlah file berasal dari video yang dipilih pengguna. Contoh pada tampilan awal adalah contoh kueri, bukan hasil atau statistik fiktif.
