# CRM Synagogue Charenton

Application web installable (PWA) de gestion des dons et promesses de don
de la Synagogue de Charenton. Conçue **mobile-first** : iPhone d'abord,
puis tablette, puis ordinateur.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `index.html` | L'application complète (React + Tailwind + Supabase, autonome) |
| `manifest.json` | Manifeste PWA (nom, icônes, couleurs, mode standalone) |
| `sw.js` | Service Worker (cache, mode hors-ligne, mise à jour auto) |
| `icon-192.png` `icon-512.png` `apple-touch-icon.png` | Icônes de l'application |
| `schema.sql` | Schéma de base de données (référence / reconstruction) |

## Connexion par nom (sans email)

Les utilisateurs se connectent avec **leur nom** (prénom, ou prénom et nom)
et un mot de passe — aucune adresse email n'est demandée.

En interne, le nom est transformé en identifiant technique pour Supabase
(ex. « David Cohen » → `david-cohen@synagogue-charenton.fr`). Les accents
et espaces sont gérés automatiquement. Deux personnes portant le même nom
doivent être distinguées (ex. « David Cohen » et « David Cohen B »).

## Hébergement

Le dépôt se déploie tel quel sur Hostinger (déploiement automatique via
le webhook configuré), Vercel, Netlify ou GitHub Pages. Les fichiers
doivent rester à la **racine** du site.

## Base de données — déjà configurée

Un projet Supabase dédié a été créé : **synagogue-charenton** (région Paris).
L'URL et la clé publique sont déjà intégrées dans `index.html`. Le schéma,
les déclencheurs et la sécurité (RLS) sont en place.

### ⚠️ Une seule action manuelle restante

Pour que la création de comptes depuis l'écran « Gérer les utilisateurs »
fonctionne, il faut désactiver la confirmation d'email :

1. Tableau de bord Supabase → projet **synagogue-charenton**
2. **Authentication → Sign In / Providers → Email**
3. Décocher **« Confirm email »** puis enregistrer

## Compte super administrateur

- **Nom de connexion :** `Admin`
- **Mot de passe :** communiqué séparément dans la conversation

Ce compte peut tout faire, y compris créer et gérer les autres comptes.

## Mot de passe oublié

Il n'y a pas de réinitialisation par email (puisqu'il n'y a pas d'email).
Un super administrateur peut réinitialiser le mot de passe d'un membre
depuis le tableau de bord Supabase : **Authentication → Users**, choisir
l'utilisateur, puis « Reset password » / « Send recovery ».

## Rôles

- **super_admin** — tout, plus la gestion des utilisateurs
- **user** — consultation et gestion des dons et promesses

## Installation sur téléphone

- **iPhone / iPad :** ouvrir le site dans Safari → bouton Partager →
  « Sur l'écran d'accueil »
- **Android :** un bandeau « Installer l'application » s'affiche, ou
  menu de Chrome → « Installer l'application »
