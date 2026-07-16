-- =====================================================================
-- SKEMA DATABASE — Aplikasi Sampling Timbulan Sampah Organik Tulungagung
-- Jalankan seluruh file ini di Supabase: Dashboard > SQL Editor > New query
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. EKSTENSI
-- ---------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. PROFIL PETUGAS (terhubung ke auth.users bawaan Supabase)
-- ---------------------------------------------------------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'enumerator' check (role in ('admin','enumerator')),
  created_at timestamptz not null default now()
);

-- Otomatis buat baris profil saat user baru mendaftar
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'enumerator')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------------------------------------------------------------------
-- 2. PARAMETER (sheet: PARAMETER)
-- ---------------------------------------------------------------------
create table if not exists parameter (
  key text primary key,
  nilai_numeric numeric,
  nilai_text text,
  satuan text,
  keterangan text
);

insert into parameter (key, nilai_numeric, nilai_text, satuan, keterangan) values
  ('jumlah_strata', 4, null, 'strata', '4 strata disederhanakan.'),
  ('desa_per_strata', 3, null, 'desa', 'Masing-masing 3 desa.'),
  ('total_desa_sampel', 12, null, 'desa', '4 x 3.'),
  ('responden_per_desa', 30, null, 'RT', 'Target responden.'),
  ('subsample_timbang_per_desa', 10, null, 'RT', 'Target sub-sampel timbang.'),
  ('hari_penimbangan', 8, null, 'hari', 'Ditetapkan 8 hari.'),
  ('koefisien_timbulan_default', 0.38, null, 'kg/orang/hari', 'Parameter pembanding.'),
  ('persen_organik_default', 0.6, null, '%', 'Parameter pembanding.'),
  ('ambang_selisih_rekonsiliasi', 0.01, null, 'kg', 'Toleransi selisih penimbangan-rincian.'),
  ('rasio_verifikasi_min', 0.98, null, 'rasio', 'Ambang minimal rasio rekonsiliasi OK untuk status layak.'),
  ('status_layak', null, 'LAYAK ESTIMASI TERVERIFIKASI', 'status', 'Kriteria output.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 3. KLASIFIKASI PRAKTIK (sheet: KLASIFIKASI PRAKTIK)
-- ---------------------------------------------------------------------
create table if not exists klasifikasi_praktik (
  kode text primary key,
  praktik text not null,
  status_penghitungan text not null,
  syarat_minimal text,
  faktor_praktek numeric not null default 0,
  catatan text
);

insert into klasifikasi_praktik (kode, praktik, status_penghitungan, syarat_minimal, faktor_praktek, catatan) values
  ('O1','Sisa makanan diberikan ke ternak','dihitung','Rutin; organik bersih; tidak tercampur residu; ada bukti.',1.0,'Tidak menghitung makanan sengaja untuk pakan.'),
  ('O2','Komposting rumah tangga','dihitung','Ada komposter/lubang/proses aktif; tidak dibakar.',1.0,'Komposter tidak aktif tidak dihitung.'),
  ('O3','Komposting komunal/desa/sekolah/pasar','dihitung','Ada lokasi, pengelola, logbook, bukti aktivitas.',1.0,'Cegah double counting.'),
  ('O4','Jogangan organik bersih','dihitung','Hanya organik; jauh dari sumur/sungai; tidak dibakar.',0.8,'Dihitung konservatif.'),
  ('O5','Serasah/daun dikelola sengaja','dihitung','Dikelola sebagai kompos/mulsa; tidak dibakar.',0.7,'Serasah alami tidak dihitung.'),
  ('R1','Organik dicampur dan diangkut','tidak dihitung sebagai pengurangan organik','Dicatat sebagai residu/penanganan.',0.0,'Beban sistem angkut/TPA.'),
  ('R2','Sampah dibakar','tidak dihitung','Tidak ada.',0.0,'Praktik tidak aman.'),
  ('R3','Dibuang ke lingkungan','tidak dihitung','Tidak ada.',0.0,'Tidak terkelola.'),
  ('R4','Data belum dapat diverifikasi','tidak dihitung','Perlu bukti tambahan.',0.0,'Tidak dipakai sampai terverifikasi.')
on conflict (kode) do nothing;

-- ---------------------------------------------------------------------
-- 4. FORM1 — PROFIL DESA
-- ---------------------------------------------------------------------
create table if not exists desa (
  kode_desa text primary key,
  nama_desa text not null,
  kecamatan text,
  strata text not null check (strata in (
    'Perdesaan datar/pertanian','Peri-urban/berkembang',
    'Pegunungan/sulit akses','Desa dengan modal pengelolaan/risiko lingkungan')),
  penduduk integer not null default 0,
  jumlah_rt integer not null default 0,
  ada_fasilitas_organik boolean not null default false,
  ada_layanan_angkut text,
  risiko_lingkungan text,
  catatan text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 5. FORM2 — SURVEI OBSERVASI 12Q
-- ---------------------------------------------------------------------
create table if not exists form2_survei (
  id uuid primary key default gen_random_uuid(),
  id_rt text unique not null,
  kode_desa text not null references desa(kode_desa),
  tanggal date not null default current_date,
  enumerator text,
  jumlah_anggota integer,
  subsample_timbang boolean not null default false,
  q1_pengelola_sampah text,
  q2_praktik_sisa_makanan text,
  q3_organik_dipilah text,
  q4_ada_ternak text,
  q5_praktik_daun_halaman text,
  q6_komposter_jogangan text,
  q7_organik_bersih text,
  q8_praktik_anorganik text,
  q9_pembakaran text,
  q10_buang_lingkungan text,
  q11_layanan_angkut text,
  q12_hambatan_utama text,
  bukti_minimal text,
  catatan text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_form2_desa on form2_survei(kode_desa);

-- ---------------------------------------------------------------------
-- 6. FORM3 — PENIMBANGAN 8 HARI
-- ---------------------------------------------------------------------
create table if not exists form3_penimbangan (
  id uuid primary key default gen_random_uuid(),
  tanggal date not null,
  hari_ke integer not null check (hari_ke between 1 and 8),
  kode_desa text not null references desa(kode_desa),
  id_rt text not null references form2_survei(id_rt),
  jumlah_anggota integer,
  organik_total numeric not null default 0,
  anorganik_bernilai numeric not null default 0,
  residu numeric not null default 0,
  total_sampah numeric generated always as (organik_total + anorganik_bernilai + residu) stored,
  catatan text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (id_rt, hari_ke)
);
create index if not exists idx_form3_desa on form3_penimbangan(kode_desa);

-- ---------------------------------------------------------------------
-- 7. FORM4 — VALIDASI & REKAP (rincian per praktik + rekonsiliasi)
-- ---------------------------------------------------------------------
create table if not exists form4_validasi (
  id uuid primary key default gen_random_uuid(),
  tanggal date not null,
  hari_ke integer not null check (hari_ke between 1 and 8),
  kode_desa text not null references desa(kode_desa),
  id_rt text not null references form2_survei(id_rt),
  organik_terukur numeric not null default 0,
  o1 numeric not null default 0,
  o2 numeric not null default 0,
  o3 numeric not null default 0,
  o4 numeric not null default 0,
  o5 numeric not null default 0,
  r1 numeric not null default 0,
  r2 numeric not null default 0,
  r3 numeric not null default 0,
  r4 numeric not null default 0,
  bukti_wawancara boolean not null default false,
  bukti_observasi boolean not null default false,
  bukti_timbang boolean not null default false,
  bukti_foto_logbook boolean not null default false,
  catatan text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (id_rt, hari_ke)
);
create index if not exists idx_form4_desa on form4_validasi(kode_desa);

-- =====================================================================
-- VIEW: v_form4_validasi
-- Mereplikasi kolom S–X di sheet FORM4 VALIDASI REKAP
-- =====================================================================
create or replace view v_form4_validasi as
select
  f.*,
  case
    when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) >= 3 then 1.0
    when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 2 then 0.75
    when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 1 then 0.5
    else 0
  end as faktor_bukti,
  (f.o1+f.o2+f.o3+f.o4+f.o5+f.r1+f.r2+f.r3+f.r4) as total_rincian,
  abs(f.organik_terukur - (f.o1+f.o2+f.o3+f.o4+f.o5+f.r1+f.r2+f.r3+f.r4)) as selisih,
  ((f.o1 + f.o2 + f.o3 + f.o4*0.8 + f.o5*0.7) *
    (case
      when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) >= 3 then 1.0
      when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 2 then 0.75
      when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 1 then 0.5
      else 0
    end)) as organik_terkoreksi,
  case when f.organik_terukur = 0 then 0 else
    ((f.o1 + f.o2 + f.o3 + f.o4*0.8 + f.o5*0.7) *
      (case
        when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) >= 3 then 1.0
        when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 2 then 0.75
        when (f.bukti_wawancara::int + f.bukti_observasi::int + f.bukti_timbang::int + f.bukti_foto_logbook::int) = 1 then 0.5
        else 0
      end)) / f.organik_terukur
  end as rasio_terkoreksi,
  case
    when abs(f.organik_terukur - (f.o1+f.o2+f.o3+f.o4+f.o5+f.r1+f.r2+f.r3+f.r4))
      <= (select nilai_numeric from parameter where key = 'ambang_selisih_rekonsiliasi')
    then 'OK' else 'CEK SELISIH'
  end as status_rekonsiliasi
from form4_validasi f;

-- =====================================================================
-- VIEW: v_rekap_desa  (replikasi sheet REKAP DESA)
-- hari_timbang_aktual = jumlah baris FORM3 desa tsb / Subsample Timbang (FORM2),
-- persis rumus asli: COUNTIFS(FORM3,desa)/F (F = subsample timbang desa itu)
-- =====================================================================
create or replace view v_rekap_desa as
select
  d.kode_desa,
  d.nama_desa,
  d.strata as tipologi,
  d.penduduk,
  coalesce(s.responden_survei, 0)   as responden_survei,
  coalesce(s.subsample_timbang, 0)  as subsample_timbang,
  case when coalesce(s.subsample_timbang,0) = 0 then 0
       else coalesce(w.baris_timbang,0)::numeric / s.subsample_timbang end as hari_timbang_aktual,
  coalesce(w.total_jiwa_hari, 0)    as total_jiwa_hari,
  coalesce(w.organik_terukur, 0)    as organik_terukur_kg,
  coalesce(v.organik_terkoreksi, 0) as organik_terkoreksi_kg,
  coalesce(v.rasio_rekonsiliasi_ok, 0) as rasio_rekonsiliasi_ok,
  case when coalesce(w.organik_terukur,0) = 0 then 0
       else coalesce(v.organik_terkoreksi,0) / w.organik_terukur end as faktor_verifikasi_tertimbang,
  case when coalesce(w.total_jiwa_hari,0) = 0 then 0
       else coalesce(v.organik_terkoreksi,0) / w.total_jiwa_hari end as organik_terkoreksi_kg_org_hari,
  (case when coalesce(w.total_jiwa_hari,0) = 0 then 0
        else coalesce(v.organik_terkoreksi,0) / w.total_jiwa_hari end) * d.penduduk as estimasi_terverifikasi_kg_hari,
  (case when coalesce(w.total_jiwa_hari,0) = 0 then 0
        else coalesce(v.organik_terkoreksi,0) / w.total_jiwa_hari end) * d.penduduk * 365 / 1000 as estimasi_terverifikasi_ton_tahun,
  case when
      coalesce(s.responden_survei,0) >= (select nilai_numeric from parameter where key='responden_per_desa')
      and coalesce(s.subsample_timbang,0) >= (select nilai_numeric from parameter where key='subsample_timbang_per_desa')
      and (case when coalesce(s.subsample_timbang,0) = 0 then 0 else coalesce(w.baris_timbang,0)::numeric / s.subsample_timbang end)
          >= (select nilai_numeric from parameter where key='hari_penimbangan')
      and coalesce(v.rasio_rekonsiliasi_ok,0) >= (select nilai_numeric from parameter where key='rasio_verifikasi_min')
    then (select nilai_text from parameter where key='status_layak')
    else 'PERLU VERIFIKASI'
  end as status_kelayakan
from desa d
left join (
  select kode_desa,
         count(*)                                 as responden_survei,
         count(*) filter (where subsample_timbang) as subsample_timbang
  from form2_survei group by kode_desa
) s on s.kode_desa = d.kode_desa
left join (
  select kode_desa,
         count(*)            as baris_timbang,
         sum(jumlah_anggota)  as total_jiwa_hari,
         sum(organik_total)   as organik_terukur
  from form3_penimbangan group by kode_desa
) w on w.kode_desa = d.kode_desa
left join (
  select kode_desa,
         sum(organik_terkoreksi) as organik_terkoreksi,
         case when count(*) = 0 then 0
              else count(*) filter (where status_rekonsiliasi = 'OK')::numeric / count(*) end as rasio_rekonsiliasi_ok
  from v_form4_validasi group by kode_desa
) v on v.kode_desa = d.kode_desa;

-- =====================================================================
-- VIEW: v_rekap_tipologi (replikasi sheet REKAP Tipologi)
-- =====================================================================
create or replace view v_rekap_tipologi as
select
  tipologi,
  count(*) as jumlah_desa,
  sum(penduduk) as penduduk,
  sum(responden_survei) as responden_survei,
  sum(subsample_timbang) as subsample_timbang,
  sum(estimasi_terverifikasi_kg_hari) as estimasi_terverifikasi_kg_hari,
  sum(estimasi_terverifikasi_ton_tahun) as estimasi_terverifikasi_ton_tahun,
  case when sum(penduduk) = 0 then 0 else sum(estimasi_terverifikasi_kg_hari) / sum(penduduk) end as kg_org_hari_tertimbang,
  case when count(*) = count(*) filter (where status_kelayakan = (select nilai_text from parameter where key='status_layak'))
       then 'LAYAK' else 'PERLU VERIFIKASI' end as status
from v_rekap_desa
group by tipologi;

-- =====================================================================
-- VIEW: v_data_akhir_kabupaten (replikasi sheet DATA AKHIR KABUPATEN)
-- =====================================================================
create or replace view v_data_akhir_kabupaten as
select
  (select count(*) from v_rekap_tipologi) as jumlah_strata,
  (select count(*) from desa) as jumlah_desa_sampel,
  (select coalesce(sum(responden_survei),0) from v_rekap_desa) as jumlah_responden_survei,
  (select coalesce(sum(subsample_timbang),0) from v_rekap_desa) as jumlah_subsample_timbang,
  (select nilai_numeric from parameter where key='hari_penimbangan') as hari_penimbangan_ditetapkan,
  (select coalesce(avg(hari_timbang_aktual),0) from v_rekap_desa) as rata_rata_hari_timbang_aktual,
  (select coalesce(sum(penduduk),0) from v_rekap_desa) as total_penduduk_desa_sampel,
  (select coalesce(sum(organik_terukur_kg),0) from v_rekap_desa) as total_organik_terukur,
  (select coalesce(sum(organik_terkoreksi_kg),0) from v_rekap_desa) as total_organik_terkoreksi,
  case when (select coalesce(sum(organik_terukur_kg),0) from v_rekap_desa) = 0 then 0
       else (select sum(organik_terkoreksi_kg) from v_rekap_desa) / (select sum(organik_terukur_kg) from v_rekap_desa)
  end as faktor_verifikasi_tertimbang_kabupaten,
  case when (select coalesce(sum(total_jiwa_hari),0) from v_rekap_desa) = 0 then 0
       else (select sum(organik_terkoreksi_kg) from v_rekap_desa) / (select sum(total_jiwa_hari) from v_rekap_desa)
  end as rata_rata_organik_terkoreksi_kg_org_hari,
  (select coalesce(sum(estimasi_terverifikasi_kg_hari),0) from v_rekap_desa) as estimasi_kg_hari,
  (select coalesce(sum(estimasi_terverifikasi_kg_hari),0) * 365 / 1000 from v_rekap_desa) as estimasi_ton_tahun,
  case when (select count(*) from v_rekap_desa where status_kelayakan = (select nilai_text from parameter where key='status_layak'))
            = (select count(*) from desa)
       then (select nilai_text from parameter where key='status_layak')
       else 'PERLU VERIFIKASI'
  end as status_kelayakan_data;

-- =====================================================================
-- 8. ROW LEVEL SECURITY
-- =====================================================================
alter table profiles enable row level security;
alter table parameter enable row level security;
alter table klasifikasi_praktik enable row level security;
alter table desa enable row level security;
alter table form2_survei enable row level security;
alter table form3_penimbangan enable row level security;
alter table form4_validasi enable row level security;

-- profiles: setiap user lihat semua profil (untuk atribusi), edit hanya milik sendiri; admin bebas edit
drop policy if exists "profiles_select_all" on profiles;
create policy "profiles_select_all" on profiles for select using (auth.role() = 'authenticated');
drop policy if exists "profiles_update_own" on profiles;
create policy "profiles_update_own" on profiles for update using (auth.uid() = id or is_admin());

-- parameter & klasifikasi_praktik: semua yang login boleh baca, hanya admin boleh ubah
drop policy if exists "parameter_select" on parameter;
create policy "parameter_select" on parameter for select using (auth.role() = 'authenticated');
drop policy if exists "parameter_admin_write" on parameter;
create policy "parameter_admin_write" on parameter for all using (is_admin()) with check (is_admin());

drop policy if exists "klasifikasi_select" on klasifikasi_praktik;
create policy "klasifikasi_select" on klasifikasi_praktik for select using (auth.role() = 'authenticated');
drop policy if exists "klasifikasi_admin_write" on klasifikasi_praktik;
create policy "klasifikasi_admin_write" on klasifikasi_praktik for all using (is_admin()) with check (is_admin());

-- desa: semua yang login boleh baca; hanya admin tambah/ubah/hapus
drop policy if exists "desa_select" on desa;
create policy "desa_select" on desa for select using (auth.role() = 'authenticated');
drop policy if exists "desa_admin_write" on desa;
create policy "desa_admin_write" on desa for all using (is_admin()) with check (is_admin());

-- form2/form3/form4: semua yang login boleh baca (koordinasi lintas enumerator);
-- setiap petugas boleh input baru; hanya boleh ubah/hapus data miliknya sendiri, admin bebas.
drop policy if exists "form2_select" on form2_survei;
create policy "form2_select" on form2_survei for select using (auth.role() = 'authenticated');
drop policy if exists "form2_insert" on form2_survei;
create policy "form2_insert" on form2_survei for insert with check (auth.role() = 'authenticated');
drop policy if exists "form2_update_own" on form2_survei;
create policy "form2_update_own" on form2_survei for update using (created_by = auth.uid() or is_admin());
drop policy if exists "form2_delete_own" on form2_survei;
create policy "form2_delete_own" on form2_survei for delete using (created_by = auth.uid() or is_admin());

drop policy if exists "form3_select" on form3_penimbangan;
create policy "form3_select" on form3_penimbangan for select using (auth.role() = 'authenticated');
drop policy if exists "form3_insert" on form3_penimbangan;
create policy "form3_insert" on form3_penimbangan for insert with check (auth.role() = 'authenticated');
drop policy if exists "form3_update_own" on form3_penimbangan;
create policy "form3_update_own" on form3_penimbangan for update using (created_by = auth.uid() or is_admin());
drop policy if exists "form3_delete_own" on form3_penimbangan;
create policy "form3_delete_own" on form3_penimbangan for delete using (created_by = auth.uid() or is_admin());

drop policy if exists "form4_select" on form4_validasi;
create policy "form4_select" on form4_validasi for select using (auth.role() = 'authenticated');
drop policy if exists "form4_insert" on form4_validasi;
create policy "form4_insert" on form4_validasi for insert with check (auth.role() = 'authenticated');
drop policy if exists "form4_update_own" on form4_validasi;
create policy "form4_update_own" on form4_validasi for update using (created_by = auth.uid() or is_admin());
drop policy if exists "form4_delete_own" on form4_validasi;
create policy "form4_delete_own" on form4_validasi for delete using (created_by = auth.uid() or is_admin());

-- Selesai. Lanjutkan dengan mengisi tabel `desa` (FORM1 PROFIL DESA) via aplikasi.
