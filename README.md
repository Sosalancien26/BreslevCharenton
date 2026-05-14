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
| `schema.sql` | Schéma complet de la base (référence / reconstruction) |

## Connexion par nom (sans email)

Les utilisateurs se connectent avec **leur nom** (prénom, ou prénom et nom)
et un mot de passe — aucune adresse email n'est demandée. En interne, le nom
est transformé en identifiant technique (« David Cohen » →
`david-cohen@synagogue-charenton.fr`). Accents et espaces gérés
automatiquement. Deux personnes du même nom doivent être distinguées.

## Fonctionnalités

- **Promesses & dons** — saisie, suivi, recherche, filtres, KPI en temps réel
- **Moyen de paiement** — Carte bleue, Virement, Espèces, Chèque, Prélèvement, Autre
- **Reçus fiscaux (CERFA)** — téléversement et conservation des documents
  (PDF ou photo), case « CERFA envoyé » avec date
- **Historique des relances** — chaque relance est datée et comptée
- **Journal d'audit** (super admin) — qui a ajouté, modifié, supprimé un don,
  qui a validé un paiement, qui a créé ou modifié un compte
- **Export CSV** — promesses et dons, compatible Excel
- **Pagination** — listes paginées (50 par page) pour rester fluide à grande échelle
- **PWA** — installable et utilisable comme une vraie application

## Base de données — déjà configurée

Projet Supabase dédié : **synagogue-charenton** (région Paris).
L'URL et la clé publique sont intégrées dans `index.html`. Le schéma,
les déclencheurs, la sécurité (RLS), le stockage des CERFA et la fonction
serveur de création de comptes sont en place.

> Aucune action manuelle Supabase n'est requise. La création de comptes
> passe par une fonction serveur sécurisée (Edge Function `create-user`)
> qui crée les comptes déjà confirmés, sans envoi d'email.

## Compte super administrateur

- **Nom de connexion :** `Admin`
- **Mot de passe :** communiqué séparément dans la conversation

Ce compte peut tout faire, y compris créer et gérer les autres comptes.

## Mot de passe oublié

Pas de réinitialisation par email (il n'y a pas d'email). Un super
administrateur réinitialise le mot de passe d'un membre depuis le tableau
de bord Supabase : **Authentication → Users**.

## Rôles

- **super_admin** — tout, plus la gestion des comptes et le journal d'audit
- **user** — consultation et gestion des dons et promesses

## Hébergement

Le dépôt se déploie tel quel sur Hostinger (déploiement automatique via
le webhook), Vercel, Netlify ou GitHub Pages. Les fichiers restent à la
**racine** du site.

## Installation sur téléphone

- **iPhone / iPad :** Safari → bouton Partager → « Sur l'écran d'accueil »
- **Android :** bandeau « Installer l'application », ou menu Chrome →
  « Installer l'application »
