# Spidolin

**Coret-coret di layar Mac Anda.** Aplikasi anotasi layar native untuk macOS, ditulis
dengan Swift/AppKit dan terinspirasi oleh [Gromit-MPX](https://github.com/bk138/gromit-mpx).

🇬🇧 Read in English: [README.md](README.md)

Spidolin tinggal di menu bar dan memungkinkan Anda menggambar di atas apa pun yang
tampil di layar (slide, kode, video, aplikasi layar penuh) saat presentasi, berbagi
layar, atau merekam. Spidolin ditulis ulang dengan Swift/AppKit, bukan hasil porting,
karena Gromit-MPX bergantung pada X11/XInput (penangkapan tombol global, multi-pointer)
yang tidak ada di macOS.

## Fitur

- Menggambar di semua layar, semua Space, dan di atas aplikasi layar penuh
- Alat: pena, stabilo, panah, garis, persegi panjang, elips, penghapus
- 8 warna dan ketebalan garis yang bisa diatur
- Tekanan pena tablet (Wacom dan lain-lain) mengubah ketebalan garis
- Undo/redo (100 langkah), termasuk membersihkan layar yang bisa di-undo
- Sembunyikan/tampilkan coretan tanpa menghapusnya
- Tombol pintas global yang sama dengan Gromit-MPX (F9, F8, …)
- Tidak pernah merebut fokus keyboard dari aplikasi yang sedang dipresentasikan
- Kendali lewat baris perintah (`--toggle`, `--clear`, …) seperti `gromit-mpx`
- Berjalan otomatis saat login
- Tidak memerlukan izin Accessibility

## Kebutuhan

- macOS 13 (Ventura) atau yang lebih baru
- Xcode Command Line Tools, untuk build (`xcode-select --install`)

## Build dan instalasi

```bash
git clone https://github.com/saidfauzul/spidolin.git
cd spidolin
./build.sh
open build/Spidolin.app
```

Ikon pensil akan muncul di menu bar.

Untuk memasang ke `~/Applications` (disarankan, dan lokasi yang stabil untuk
"Launch at login"):

```bash
bash build.sh install
open ~/Applications/Spidolin.app
```

Hasil build ditandatangani secara ad-hoc. Jika Anda mengunduh versi siap pakai,
macOS mungkin memblokirnya saat pertama dibuka; klik kanan aplikasinya lalu pilih Open.

## Cara pakai

### Tombol pintas global

| Tombol | Fungsi | Padanan di Gromit-MPX |
|---|---|---|
| F9 atau ⌃⌥D | Mulai/berhenti menggambar | F9 |
| ⇧F9 atau ⌃⌥C | Bersihkan layar (bisa di-undo) | Shift-F9 |
| ⌃F9 atau ⌃⌥H | Sembunyikan/tampilkan coretan | Ctrl-F9 |
| ⌥F9 | Keluar | Alt-F9 |
| F8 atau ⌃⌥Z | Undo | F8 |
| ⇧F8 atau ⌃⌥⇧Z | Redo | Shift-F8 |

Di MacBook, F8/F9 adalah tombol media, jadi tekan Fn+F9 atau gunakan ⌃⌥D.

### Saat menggambar

Tombol-tombol ini hanya ditangkap ketika mode menggambar aktif:

- `P` pena, `M` stabilo, `A` panah, `L` garis, `R` persegi panjang, `O` elips, `E` penghapus
- `1`–`8` warna (merah, biru, hijau, kuning, oranye, ungu, putih, hitam)
- `[` / `]` ketebalan, `⌘Z` / `⌘⇧Z` undo/redo, `Delete` bersihkan, `Esc` selesai
- Klik kanan + seret = penghapus (seperti Button3 di Gromit-MPX)
- Tahan Shift saat mulai menyeret = garis lurus dengan alat yang sedang dipilih

Semua fungsi ini juga tersedia dari menu ikon pensil.

## Baris perintah

Seperti `gromit-mpx --toggle`, Spidolin yang sedang berjalan bisa dikendalikan dari Terminal:

```bash
~/Applications/Spidolin.app/Contents/MacOS/Spidolin --toggle   # -t
```

| Opsi | Fungsi |
|---|---|
| `--toggle`, `-t` | Mulai/berhenti menggambar |
| `--clear`, `-c` | Bersihkan layar |
| `--undo`, `-z` | Undo |
| `--redo`, `-y` | Redo |
| `--visibility`, `-v` | Sembunyikan/tampilkan coretan |
| `--quit`, `-q` | Keluar |

## Berjalan saat login

Aktifkan atau matikan dari menu ikon pensil > "Launch at login". Jika macOS meminta
persetujuan, System Settings > General > Login Items akan terbuka; pengaturan yang
sama juga bisa diubah di sana.

## Arsitektur

- `Sources/Overlay.swift`: satu `NSPanel` transparan tanpa bingkai untuk setiap layar,
  pada level screen saver, hadir di semua Space dan di atas aplikasi layar penuh.
  Panel ini tidak pernah mengaktifkan aplikasi, sehingga fokus keyboard tetap pada
  aplikasi yang sedang dipresentasikan. Saat mode menggambar mati, panel meneruskan
  klik ke bawahnya (`ignoresMouseEvents`).
- `Sources/Ink.swift`: dokumen vektor (koordinat layar global, sehingga satu goresan
  bisa melintasi beberapa layar), undo/redo berbasis snapshot, dan renderer Core
  Graphics. Goresan yang sudah selesai disimpan sebagai bitmap; hanya goresan yang
  sedang dibuat yang digambar ulang setiap kali mouse bergerak.
- `Sources/HotKeys.swift`: tombol pintas global melalui Carbon `RegisterEventHotKey`.
- `Sources/AppController.swift`: ikon menu bar, pemilihan alat/warna/ketebalan, dan perintah.
- `Sources/main.swift`: titik masuk aplikasi dan perintah baris perintah (melalui distributed notification).

## Rencana pengembangan

Belum diimplementasikan dibandingkan dengan Gromit-MPX:

- Berkas konfigurasi alat (alat, warna, dan tombol pintas kustom)
- Alat SMOOTH dan ORTHOGONAL
- Pengaturan opasitas
- Multi-pointer (MPX tidak punya padanan di macOS, jadi kemungkinan kecil akan dibuat)

## Berkontribusi

Laporan bug dan pull request sangat diterima. Lihat [CONTRIBUTING.md](CONTRIBUTING.md).

## Lisensi

Hak cipta © 2026 Said Fauzul. Spidolin adalah perangkat lunak bebas di bawah GNU GPL
versi 2 atau yang lebih baru (lihat [LICENSE](LICENSE)). Spidolin adalah penulisan
ulang independen dalam Swift yang terinspirasi oleh Gromit-MPX karya Christian Beier
dan para kontributornya; Spidolin tidak memuat kode Gromit-MPX sama sekali.
