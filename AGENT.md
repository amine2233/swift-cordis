# swift-cordis

Portage Swift 6 non officiel du principe Cordis (architecture « tout est un plugin »,
composabilité spatio-temporelle). Architecture et décisions : `docs/ARCHITECTURE.md` — à lire avant toute modification.

## Commandes
- Build : `swift build`
- Tests : `swift test`
- Démo : `swift run cordis-demo`

## Conventions
- Swift 6, strict concurrency. Toute mutation du graphe passe par `@CordisActor`.
- Modules : `CordisKernel` (noyau, zéro sucre) et `Cordis` (API publique, ré-exporte le noyau).
- Clés de service typées (`ServiceKey`), jamais de chaînes.
- Tests avec Swift Testing (`import Testing`, `@Test`, `#expect`). TDD : écrire le test d'un invariant avant de le corriger.
- Pas de `Task {}` fire-and-forget dans le noyau : l'ordre des événements doit rester déterministe.
- Code et commentaires en anglais ; docs utilisateur (README) en anglais avec la mention d'attribution Cordis en tête.
