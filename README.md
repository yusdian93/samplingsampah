# Aplikasi Sampling Organik Tulungagung

Aplikasi web untuk menggantikan workbook `FIX_WORKBOOK_SAMPLING_ORGANIK_TULUNGAGUNG.xlsx`.
Semua rumus di sheet **REKAP DESA**, **REKAP Tipologi**, **DATA AKHIR KABUPATEN**, dan
**FORM4 VALIDASI REKAP** direplikasi sebagai VIEW di database Supabase, jadi hasilnya
**otomatis ter-update** setiap kali ada data survei/timbang/validasi baru — tidak perlu buka
Excel atau hitung manual lagi.

## Isi paket
| File | Fungsi |
|---|---|
| `schema.sql` | Skema database: tabel, keamanan (RLS), dan VIEW rekap otomatis |
| `supabase-adapter.js` | Penghubung antara aplikasi dan Supabase (auth + CRUD) |
| `index.html` | Antarmuka aplikasi (login, form input, dashboard, rekap) |

## Langkah instalasi

### 1. Buat proyek Supabase (gratis)
1. Buka [supabase.com](https://supabase.com) → **New project**.
2. Catat **Project URL** dan **anon public key** (Settings → API).

### 2. Jalankan skema database
1. Di dashboard Supabase, buka **SQL Editor → New query**.
2. Salin seluruh isi `schema.sql`, tempel, lalu **Run**.
3. Ini akan membuat semua tabel (desa, form2_survei, form3_penimbangan,
   form4_validasi, parameter, klasifikasi_praktik, profiles) beserta VIEW
   rekapnya, dan mengisi parameter + klasifikasi praktik sesuai pedoman.

### 3. Hubungkan aplikasi ke proyek Anda
Buka `supabase-adapter.js`, ganti dua baris ini dengan nilai proyek Anda:
```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```

### 4. Jalankan aplikasi
`index.html` adalah aplikasi statis biasa — cukup:
- buka langsung di browser (double-click), **atau**
- upload ketiga file ke hosting statis apa pun (Netlify, Vercel, GitHub Pages,
  atau folder di Google Drive dengan ekstensi web hosting).

Pastikan `index.html` dan `supabase-adapter.js` berada **di folder yang sama**.

### 5. Buat akun petugas pertama (jadi admin)
1. Di aplikasi, klik **Daftar petugas baru**, isi nama, email, kata sandi.
2. Di dashboard Supabase → **Table Editor → profiles**, cari baris Anda,
   ubah kolom `role` dari `enumerator` menjadi `admin`.
3. Admin adalah satu-satunya role yang boleh menambah/mengubah **Profil Desa**
   (FORM1) dan parameter/klasifikasi praktik. Semua petugas (enumerator)
   bisa mengisi FORM2, FORM3, FORM4 dan melihat semua rekap.
4. Petugas berikutnya cukup daftar sendiri lewat halaman login (role default
   `enumerator`); admin cukup mempromosikan lewat Table Editor bila perlu.

### 6. Mulai input data — urutan yang disarankan
1. **Profil Desa** (admin): masukkan 12 desa dengan strata masing-masing.
2. **Survei 12Q**: input responden per desa (target 30, dengan 10 di antaranya
   ditandai "Sub-sampel Timbang").
3. **Penimbangan 8 Hari**: input harian untuk tiap RT sub-sampel.
4. **Validasi & Rekonsiliasi**: rincian per kode praktik (O1–O5/R1–R4) dan
   status bukti untuk setiap baris timbang.
5. **Dashboard**, **Rekap Desa**, **Rekap Tipologi** akan otomatis terisi —
   tidak ada tombol "hitung", semuanya live dari database.

## Tentang perhitungan
- Rumus faktor praktik (O4 = 0.8, O5 = 0.7, lainnya dihitung penuh = 1.0,
  R1–R4 = 0) dan ambang selisih rekonsiliasi (0.01 kg) diambil dari sheet
  `PARAMETER` dan `KLASIFIKASI PRAKTIK` pada workbook asli.
- Kriteria "LAYAK ESTIMASI TERVERIFIKASI": responden ≥ 30, sub-sampel timbang
  ≥ 10, hari timbang aktual ≥ 8, dan rasio rekonsiliasi OK ≥ 98% — persis
  seperti rumus `IF(AND(...))` di sheet REKAP DESA.
- Nilai-nilai ambang ini tersimpan di tabel `parameter` dan bisa diubah oleh
  admin lewat Table Editor Supabase jika pedoman berubah di masa depan
  (VIEW akan otomatis memakai nilai baru).

## Catatan keamanan
- Setiap tabel memakai **Row Level Security**: semua petugas yang login bisa
  membaca semua data (untuk koordinasi lintas tim), tapi hanya boleh
  mengubah/menghapus data yang mereka input sendiri (admin bisa mengubah semua).
- Jangan bagikan `anon public key` sebagai rahasia mutlak — kunci ini memang
  dirancang untuk dipakai di sisi browser, keamanan sesungguhnya ada di RLS
  yang sudah diatur `schema.sql`.
