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
