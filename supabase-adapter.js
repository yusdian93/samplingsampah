// =====================================================================
// supabase-adapter.js
// Lapisan penghubung antara antarmuka (index.html) dan Supabase.
// Isi SUPABASE_URL dan SUPABASE_ANON_KEY sebelum digunakan.
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// -------- KONFIGURASI: ganti dengan milik proyek Supabase Anda --------
const SUPABASE_URL = 'https://ophazoenwwqrzedfktzk.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_2H6UDqG1vvP-0MXh6a3pvg_uqrMU_Hl';
// ------------------------------------------------------------------

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---------------------------------------------------------------------
// AUTH
// ---------------------------------------------------------------------
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signUp(email, password, fullName) {
  const { data, error } = await supabase.auth.signUp({
    email, password,
    options: { data: { full_name: fullName } },
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}

export function onAuthChange(callback) {
  return supabase.auth.onAuthStateChange((_event, session) => callback(session));
}

export async function getMyProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).single();
  if (error) throw error;
  return data;
}

// ---------------------------------------------------------------------
// KELOLA PETUGAS (khusus admin — mengubah role user/admin)
// ---------------------------------------------------------------------
export async function listProfiles() {
  const { data, error } = await supabase.from('profiles').select('*').order('full_name');
  if (error) throw error;
  return data;
}

export async function updateProfileRole(id, role) {
  const { data, error } = await supabase.from('profiles').update({ role }).eq('id', id).select();
  if (error) throw error;
  return data;
}

// Membuat & menghapus AKUN LOGIN (bukan cuma baris profil) hanya bisa
// dilakukan lewat Edge Function 'admin-users' (butuh service role key
// yang tidak boleh ada di kode browser). Lihat README untuk cara deploy.
export async function adminCreateUser(email, password, fullName, role) {
  const { data, error } = await supabase.functions.invoke('admin-users', {
    body: { action: 'create', email, password, full_name: fullName, role },
  });
  if (error) throw error;
  if (data && data.ok === false) throw new Error(data.error);
  return data;
}

export async function adminDeleteUser(userId) {
  const { data, error } = await supabase.functions.invoke('admin-users', {
    body: { action: 'delete', user_id: userId },
  });
  if (error) throw error;
  if (data && data.ok === false) throw new Error(data.error);
  return data;
}

export async function adminResetPassword(userId, newPassword) {
  const { data, error } = await supabase.functions.invoke('admin-users', {
    body: { action: 'reset_password', user_id: userId, new_password: newPassword },
  });
  if (error) throw error;
  if (data && data.ok === false) throw new Error(data.error);
  return data;
}

// ---------------------------------------------------------------------
// PARAMETER & KLASIFIKASI PRAKTIK (referensi, umumnya hanya dibaca)
// ---------------------------------------------------------------------
export async function listParameter() {
  const { data, error } = await supabase.from('parameter').select('*').order('key');
  if (error) throw error;
  return data;
}

export async function listKlasifikasiPraktik() {
  const { data, error } = await supabase.from('klasifikasi_praktik').select('*').order('kode');
  if (error) throw error;
  return data;
}

// ---------------------------------------------------------------------
// FORM1 — PROFIL DESA
// ---------------------------------------------------------------------
export async function listDesa() {
  const { data, error } = await supabase.from('desa').select('*').order('kode_desa');
  if (error) throw error;
  return data;
}

export async function upsertDesa(row) {
  const { data, error } = await supabase.from('desa').upsert(row, { onConflict: 'kode_desa' }).select();
  if (error) throw error;
  return data;
}

export async function deleteDesa(kodeDesa) {
  const { error } = await supabase.from('desa').delete().eq('kode_desa', kodeDesa);
  if (error) throw error;
}

// ---------------------------------------------------------------------
// FORM2 — SURVEI OBSERVASI 12Q
// ---------------------------------------------------------------------
export async function listForm2(kodeDesa = null) {
  let q = supabase.from('form2_survei').select('*').order('id_rt');
  if (kodeDesa) q = q.eq('kode_desa', kodeDesa);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function insertForm2(row) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('form2_survei')
    .insert({ ...row, created_by: user?.id })
    .select();
  if (error) throw error;
  return data;
}

export async function updateForm2(id, row) {
  const { data, error } = await supabase.from('form2_survei').update(row).eq('id', id).select();
  if (error) throw error;
  return data;
}

export async function deleteForm2(id) {
  const { error } = await supabase.from('form2_survei').delete().eq('id', id);
  if (error) throw error;
}

// ---------------------------------------------------------------------
// FORM3 — PENIMBANGAN 8 HARI
// ---------------------------------------------------------------------
export async function listForm3(kodeDesa = null) {
  let q = supabase.from('form3_penimbangan').select('*').order('tanggal');
  if (kodeDesa) q = q.eq('kode_desa', kodeDesa);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function insertForm3(row) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('form3_penimbangan')
    .insert({ ...row, created_by: user?.id })
    .select();
  if (error) throw error;
  return data;
}

export async function updateForm3(id, row) {
  const { data, error } = await supabase.from('form3_penimbangan').update(row).eq('id', id).select();
  if (error) throw error;
  return data;
}

export async function deleteForm3(id) {
  const { error } = await supabase.from('form3_penimbangan').delete().eq('id', id);
  if (error) throw error;
}

// ---------------------------------------------------------------------
// FORM4 — VALIDASI & REKAP (baca dari view agar kolom hitung ikut tampil)
// ---------------------------------------------------------------------
export async function listForm4(kodeDesa = null) {
  let q = supabase.from('v_form4_validasi').select('*').order('tanggal');
  if (kodeDesa) q = q.eq('kode_desa', kodeDesa);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function insertForm4(row) {
  const { data: { user } } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('form4_validasi')
    .insert({ ...row, created_by: user?.id })
    .select();
  if (error) throw error;
  return data;
}

export async function updateForm4(id, row) {
  const { data, error } = await supabase.from('form4_validasi').update(row).eq('id', id).select();
  if (error) throw error;
  return data;
}

export async function deleteForm4(id) {
  const { error } = await supabase.from('form4_validasi').delete().eq('id', id);
  if (error) throw error;
}

// ---------------------------------------------------------------------
// REKAP & DASHBOARD (semua dihitung otomatis oleh VIEW di database)
// ---------------------------------------------------------------------
export async function getRekapDesa() {
  const { data, error } = await supabase.from('v_rekap_desa').select('*').order('kode_desa');
  if (error) throw error;
  return data;
}

export async function getRekapTipologi() {
  const { data, error } = await supabase.from('v_rekap_tipologi').select('*').order('tipologi');
  if (error) throw error;
  return data;
}

export async function getDataAkhirKabupaten() {
  const { data, error } = await supabase.from('v_data_akhir_kabupaten').select('*').single();
  if (error) throw error;
  return data;
}
