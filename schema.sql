-- ============================================================
--  CRM SYNAGOGUE CHARENTON — Schéma de base de données
--  Projet Supabase : synagogue-charenton (eu-west-3 / Paris)
--  À coller dans le SQL Editor de Supabase si vous devez
--  reconstruire la base sur un nouveau projet.
-- ============================================================

-- ---------- Table profiles ----------
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  nom text not null,
  email text not null,
  role text not null default 'user' check (role in ('super_admin', 'user')),
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Table donations ----------
create table public.donations (
  id uuid primary key default gen_random_uuid(),
  nom_donateur text not null,
  telephone text,
  email text,
  montant numeric(10,2) not null check (montant > 0),
  motif text,
  statut text not null default 'promesse' check (statut in ('promesse', 'paye')),
  date_creation timestamptz not null default now(),
  date_paiement timestamptz,
  date_relance timestamptz,
  notes text,
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create index idx_donations_statut on public.donations(statut);
create index idx_donations_date_creation on public.donations(date_creation desc);
create index idx_donations_nom on public.donations(nom_donateur);

-- ---------- Trigger : création automatique du profil ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nom, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nom', split_part(new.email, '@', 1)),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'user')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- Trigger : updated_at ----------
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger donations_updated_at
  before update on public.donations
  for each row execute procedure public.handle_updated_at();

-- ============================================================
--  FONCTIONS D'AIDE — SECURITY DEFINER
--  Important : les politiques RLS d'origine interrogeaient la
--  table "profiles" depuis une politique de "profiles" elle-même,
--  ce qui provoque une RÉCURSION INFINIE au moment de l'exécution
--  (erreur « infinite recursion detected in policy »).
--  Ces deux fonctions, exécutées en SECURITY DEFINER, contournent
--  la RLS et cassent la récursion. Les politiques s'appuient
--  dessus au lieu de faire un sous-select direct.
-- ============================================================
create or replace function public.is_super_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin'
  );
$$;

create or replace function public.is_active_user()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and actif = true
  );
$$;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.donations enable row level security;

-- profiles
create policy "Voir son propre profil" on public.profiles for select
  using (auth.uid() = id);
create policy "Super admin voit tout" on public.profiles for select
  using (public.is_super_admin());
create policy "Super admin gere les profils" on public.profiles for all
  using (public.is_super_admin());

-- donations
create policy "Users actifs lisent" on public.donations for select
  using (public.is_active_user());
create policy "Users actifs creent" on public.donations for insert
  with check (public.is_active_user());
create policy "Users actifs modifient" on public.donations for update
  using (public.is_active_user());
create policy "Super admin supprime" on public.donations for delete
  using (public.is_super_admin());

-- ============================================================
--  COMPTE SUPER ADMIN PAR DÉFAUT
--  Déjà créé sur le projet Supabase actuel :
--    nom de connexion : Admin
--    email technique  : admin@synagogue-charenton.fr
--    rôle             : super_admin
--
--  CONNEXION PAR NOM (sans email) :
--  L'application ne demande pas d'email. L'utilisateur saisit son
--  nom ; l'app le transforme en email technique :
--    « David Cohen » -> david-cohen@synagogue-charenton.fr
--  La colonne profiles.email stocke cet email technique ; le nom
--  affiché et saisi est profiles.nom.
--
--  Pour recréer un super admin sur un nouveau projet : créez le
--  compte via Authentication > Users (email = forme technique du
--  nom), puis exécutez :
--    update public.profiles set role = 'super_admin'
--    where email = 'EMAIL_TECHNIQUE_DE_L_ADMIN';
-- ============================================================


-- ============================================================
--  v2 — MOYEN DE PAIEMENT, CERFA, HISTORIQUE DES RELANCES,
--       JOURNAL D'AUDIT
--  (déjà appliqué au projet Supabase synagogue-charenton)
-- ============================================================

-- ----- Nouvelles colonnes sur donations -----
alter table public.donations add column if not exists moyen_paiement text;
alter table public.donations add column if not exists cerfa_envoye boolean not null default false;
alter table public.donations add column if not exists cerfa_path text;
alter table public.donations add column if not exists cerfa_date timestamptz;
alter table public.donations add column if not exists relance_count integer not null default 0;

-- ----- Historique des relances -----
create table public.relances (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id) on delete cascade,
  date_relance timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  created_by_nom text
);
create index idx_relances_donation on public.relances(donation_id);
alter table public.relances enable row level security;
create policy "Users actifs lisent les relances" on public.relances for select
  using (public.is_active_user());
create policy "Users actifs creent des relances" on public.relances for insert
  with check (public.is_active_user());

-- Synchronise donations.relance_count et donations.date_relance
create or replace function public.sync_relance_stats()
returns trigger language plpgsql security definer set search_path = public as $$
declare did uuid;
begin
  did := coalesce(new.donation_id, old.donation_id);
  update public.donations d set
    relance_count = (select count(*) from public.relances r where r.donation_id = did),
    date_relance  = (select max(r.date_relance) from public.relances r where r.donation_id = did)
  where d.id = did;
  return null;
end;
$$;
create trigger relances_sync after insert or delete on public.relances
  for each row execute procedure public.sync_relance_stats();

-- ----- Journal d'audit -----
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  resume text,
  details jsonb,
  actor_id uuid,
  actor_nom text,
  created_at timestamptz not null default now()
);
create index idx_audit_created on public.audit_log(created_at desc);
alter table public.audit_log enable row level security;
create policy "Super admin lit le journal" on public.audit_log for select
  using (public.is_super_admin());

create or replace function public.current_actor_nom()
returns text language sql security definer stable set search_path = public as $$
  select nom from public.profiles where id = auth.uid();
$$;

-- Audit des dons (création, modification, validation de paiement, suppression).
-- Les mises à jour purement techniques (synchro des relances) sont ignorées.
create or replace function public.audit_donations()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') then
    insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
    values ('don_cree', 'don', new.id,
      new.nom_donateur || ' — ' || new.montant || ' € (' || (case when new.statut = 'paye' then 'don' else 'promesse' end) || ')',
      jsonb_build_object('montant', new.montant, 'statut', new.statut, 'motif', new.motif, 'moyen_paiement', new.moyen_paiement),
      auth.uid(), public.current_actor_nom());
    return new;
  elsif (tg_op = 'UPDATE') then
    if (old.nom_donateur is not distinct from new.nom_donateur
        and old.telephone is not distinct from new.telephone
        and old.email is not distinct from new.email
        and old.montant is not distinct from new.montant
        and old.motif is not distinct from new.motif
        and old.statut is not distinct from new.statut
        and old.date_paiement is not distinct from new.date_paiement
        and old.notes is not distinct from new.notes
        and old.moyen_paiement is not distinct from new.moyen_paiement
        and old.cerfa_envoye is not distinct from new.cerfa_envoye
        and old.cerfa_path is not distinct from new.cerfa_path) then
      return new;
    end if;
    if (old.statut = 'promesse' and new.statut = 'paye') then
      insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
      values ('paiement_valide', 'don', new.id,
        'Paiement validé : ' || new.nom_donateur || ' — ' || new.montant || ' €',
        jsonb_build_object('montant', new.montant, 'moyen_paiement', new.moyen_paiement),
        auth.uid(), public.current_actor_nom());
    else
      insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
      values ('don_modifie', 'don', new.id,
        new.nom_donateur || ' — ' || new.montant || ' €',
        jsonb_build_object('montant', new.montant, 'statut', new.statut),
        auth.uid(), public.current_actor_nom());
    end if;
    return new;
  elsif (tg_op = 'DELETE') then
    insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
    values ('don_supprime', 'don', old.id,
      old.nom_donateur || ' — ' || old.montant || ' €',
      jsonb_build_object('montant', old.montant, 'statut', old.statut, 'motif', old.motif),
      auth.uid(), public.current_actor_nom());
    return old;
  end if;
  return null;
end;
$$;
create trigger audit_donations_trg after insert or update or delete on public.donations
  for each row execute procedure public.audit_donations();

-- Audit des comptes : modifications de rôle / activation.
-- (La CRÉATION d'un compte est journalisée par la fonction Edge create-user.)
create or replace function public.audit_profiles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'UPDATE') then
    if (old.role is distinct from new.role) then
      insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
      values ('compte_role', 'compte', new.id,
        new.nom || ' : rôle ' || old.role || ' → ' || new.role,
        jsonb_build_object('ancien', old.role, 'nouveau', new.role),
        auth.uid(), public.current_actor_nom());
    end if;
    if (old.actif is distinct from new.actif) then
      insert into public.audit_log(action, entity_type, entity_id, resume, details, actor_id, actor_nom)
      values ('compte_actif', 'compte', new.id,
        new.nom || ' : ' || (case when new.actif then 'compte réactivé' else 'compte désactivé' end),
        jsonb_build_object('actif', new.actif),
        auth.uid(), public.current_actor_nom());
    end if;
    return new;
  end if;
  return null;
end;
$$;
create trigger audit_profiles_trg after update on public.profiles
  for each row execute procedure public.audit_profiles();

-- ----- Stockage des documents CERFA -----
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cerfa', 'cerfa', false, 10485760,
  array['application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "cerfa - lecture users actifs" on storage.objects for select
  using (bucket_id = 'cerfa' and public.is_active_user());
create policy "cerfa - depot users actifs" on storage.objects for insert
  with check (bucket_id = 'cerfa' and public.is_active_user());
create policy "cerfa - maj users actifs" on storage.objects for update
  using (bucket_id = 'cerfa' and public.is_active_user());
create policy "cerfa - suppression super admin" on storage.objects for delete
  using (bucket_id = 'cerfa' and public.is_super_admin());

-- ============================================================
--  FONCTION EDGE — create-user
--  Déployée sur le projet Supabase (create-user). Crée les
--  comptes côté serveur avec la clé service role : compte
--  immédiatement confirmé, aucun email envoyé. Le code source
--  se trouve dans le tableau de bord Supabase > Edge Functions.
-- ============================================================


-- ============================================================
--  v3 — DURCISSEMENT SÉCURITÉ
--  (appliqué au projet ; vérifié par le linter Supabase)
-- ============================================================

-- Schéma privé : les fonctions internes ne sont plus exposées par l'API REST
create schema if not exists private;
grant usage on schema private to authenticated, anon, service_role;

create or replace function private.is_super_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'super_admin');
$$;
create or replace function private.is_active_user()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and actif = true);
$$;
create or replace function private.current_actor_nom()
returns text language sql security definer stable set search_path = public as $$
  select nom from public.profiles where id = auth.uid();
$$;
grant execute on function private.is_super_admin(), private.is_active_user(), private.current_actor_nom()
  to authenticated, anon, service_role;

-- Anciennes fonctions publiques supprimées ; toutes les politiques RLS
-- (profiles, donations, relances, audit_log, storage.objects) et les
-- triggers d'audit ont été recréés pour utiliser private.*.
-- Les politiques de "profiles" ont été regroupées en une politique propre
-- par action, et "Voir son propre profil" utilise (select auth.uid()).

-- search_path verrouillé sur handle_updated_at :
--   create or replace function public.handle_updated_at() ... set search_path = public ...

-- Fonctions de trigger retirées de la surface d'API (jamais appelées en direct) :
--   revoke all on function public.handle_new_user(), public.handle_updated_at(),
--     public.audit_donations(), public.audit_profiles(), public.sync_relance_stats()
--     from public, anon, authenticated;

-- Index sur clés étrangères :
create index if not exists idx_donations_created_by on public.donations(created_by);
create index if not exists idx_relances_created_by on public.relances(created_by);

-- ============================================================
--  FONCTIONS EDGE
--   - create-user     : création de compte (super admin), sans email
--   - reset-password  : réinitialisation du mot de passe d'un membre
--                       par un super admin (les mots de passe sont
--                       hachés et ne peuvent jamais être affichés en clair)
--
--  RESTE À FAIRE MANUELLEMENT (1 réglage dans le tableau de bord Supabase) :
--   Authentication > Policies > activer "Leaked password protection"
--   (vérifie les mots de passe contre les fuites connues — HaveIBeenPwned)
-- ============================================================


-- ============================================================
--  v4 — COFFRE DES MOTS DE PASSE (consultation par super admin)
--
--  À la demande explicite de l'administrateur : les super admins
--  peuvent consulter les mots de passe des comptes créés via l'app.
--
--  Les mots de passe restent HACHÉS côté authentification Supabase.
--  En plus, une copie CHIFFRÉE (AES-256-GCM) est conservée dans la
--  table ci-dessous, accessible UNIQUEMENT via les fonctions Edge
--  (clé service role). La clé de déchiffrement vit dans le code des
--  fonctions Edge — un export brut de la base ne révèle donc rien.
--  Compromis de sécurité accepté en connaissance de cause.
-- ============================================================
create table public.user_secrets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  secret text not null,                 -- mot de passe chiffré AES-256-GCM (base64)
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);
alter table public.user_secrets enable row level security;
-- RLS active + AUCUNE politique + privilèges révoqués : table inaccessible
-- via l'API publique. Seules les fonctions Edge (service role) y accèdent.
revoke all on public.user_secrets from anon, authenticated;

-- ============================================================
--  FONCTIONS EDGE (récapitulatif)
--   - create-user     : crée un compte + stocke le mot de passe chiffré
--   - reset-password  : réinitialise un mot de passe + met à jour le coffre
--   - get-password    : déchiffre et renvoie un mot de passe (super admin),
--                       chaque consultation est journalisée (compte_mdp_vu)
-- ============================================================
