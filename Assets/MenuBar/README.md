# Ikon menu bar Carfo

Versi monokrom dari identitas papan film dan kaca pembesar pada ikon aplikasi Carfo.

| File | Ukuran | Pemakaian |
| --- | --- | --- |
| `Carfo-menubar.png` | 22 × 22 piksel | Standar 1× |
| `Carfo-menubar@2x.png` | 44 × 44 piksel | Retina 2×, ditampilkan pada 22 × 22 pt |
| `Carfo-menubar-master.png` | 512 × 512 piksel | Master PNG transparan |
| `Carfo-menubar-preview.png` | 320 × 112 piksel | Pemeriksaan bentuk pada permukaan terang dan gelap; memiliki latar |
| `Carfo-menubar.svg` | Vektor | Sumber yang dapat diedit |

Ketiga PNG ikon berwarna hitam dengan alpha transparan. Dalam aplikasi macOS, gunakan sebagai template (`NSImage.isTemplate = true`) agar sistem memberi warna sesuai menu bar. Preview gelap menggambarkan pewarnaan template tersebut. File PNG ini belum mengganti simbol menu bar di kode aplikasi.

Aset digambar sebagai geometri vektor sederhana, lalu dirender dengan CoreGraphics. Bentuk papan film mempertahankan identitas aplikasi, kaca pembesar menunjukkan pencarian, ketebalan garis 1.5 pt menjaga keterbacaan pada ukuran kecil, dan padding mencegah bentuk menyentuh tepi. Tidak ada bayangan, efek material, atau teks karena detail tersebut mengganggu keterbacaan menu bar.

Untuk membuat ulang PNG: jalankan `swift Assets/MenuBar/render.swift "$PWD/Assets/MenuBar"` dari folder proyek.

## Pemeriksaan desain

Mode AFTER mengikuti pilihan pengguna pada sesi ini. Lingkup audit hanya aset menu bar yang baru dibuat. Tidak ada temuan yang membutuhkan persetujuan perbaikan.

Arah: utilitas menu bar untuk editor video, bahasa visual monokrom dari ikon Carfo yang sudah disetujui, ENERGY 1 / RHYTHM 1 / MOTION 1. Aset statis, fokus tunggal pada simbol pencarian footage, dengan ruang kosong untuk keterbacaan.

- Hard Gate PASS: pembuatan diminta pengguna; alpha PNG diperiksa bernilai 0–255, seluruh sudut transparan, RGB hanya hitam, dan bentuk tidak terpotong. Item teks, navigasi, formulir, keyboard, dan state aplikasi tidak berlaku untuk file ikon statis.
- Purpose Gate PASS: papan film dan kaca pembesar berasal dari identitas aplikasi serta fungsi pencarian footage; warna tunggal mendukung penggunaan sebagai template macOS; tidak ada dekorasi tanpa fungsi.
- Liveliness PASS: ENERGY 1 / RHYTHM 1 / MOTION 1 sesuai utilitas menu bar; motif film dan pencarian, satu fokus, serta ruang kosong tetap terlihat pada preview ukuran 22 dan 44 piksel.
- Craftsmanship PASS: PNG 22 × 22 dan 44 × 44 telah diperiksa secara visual pada permukaan terang dan gelap; masing-masing memiliki bounds alpha (1, 1, 20, 20) dan (3, 3, 40, 40), dengan seluruh sudut transparan. Pewarnaan terang pada preview mensimulasikan template, bukan klaim bahwa PNG hitam akan berubah warna sendiri.
