# swift-cordis — Brief d'implémentation

> Document de passation pour Claude Code. Il résume les décisions prises en amont.
> Le prototype de référence est dans `docs/reference/` : **il n'a jamais été compilé**
> (pas de toolchain Swift disponible quand il a été écrit). C'est une base de travail,
> pas du code à copier aveuglément.

## 1. Objectif

Implémenter en Swift 6 le principe de **Cordis** (noyau de Koishi, https://github.com/cordiverse/cordis),
décrit dans *A Programming Paradigm for Spatiotemporal Composability* :
**tout est un plugin**, et les plugins se composent sur deux axes.

| Axe | Question | Mécanisme |
|---|---|---|
| **Temps** | Que se passe-t-il quand un plugin est chargé, rechargé, déchargé ? | `Scope` : tout effet de bord enregistré via `ctx` est annulé automatiquement, en LIFO |
| **Espace** | Quelle instance d'un service ce plugin voit-il ? | `Slot = (service, realm)` + `ctx.isolate(Key.self, label:)` |
| **Réactivité** | Que se passe-t-il si une dépendance apparaît / change / disparaît ? | `Fork` : les dépendants passent pending → active, redémarrent, ou repassent pending |

Projet non officiel : le README doit le dire en tête et créditer Cordis avec un lien.

## 2. Nommage (décidé)

| Niveau | Nom |
|---|---|
| Repo / package SPM | `swift-cordis` |
| Module noyau | `CordisKernel` — Scope, Fork, Registry, Context, ServiceKey, Inject, Event |
| Module principal | `Cordis` — `@_exported import CordisKernel` + sucre (ServicePlugin, helpers) |
| Produits | `.library("Cordis")` (usage normal), `.library("CordisKernel")` (noyau seul) |
| Démo | `.executableTarget("CordisDemo")`, produit `cordis-demo` |
| Futures intégrations (hors périmètre) | `swift-cordis-vapor` → `CordisVapor`, `swift-cordis-swiftui` → `CordisSwiftUI` |

Plateformes : macOS 14, iOS 17, tvOS 17, watchOS 10. `swift-tools-version: 6.0`, Swift 6 language mode, strict concurrency.

## 3. État actuel du repo (commit `9670c3d`)

Squelette SPM uniquement :
- `Package.swift` en `swift-tools-version: 6.1`, plateformes macOS 14 / iOS 17, produits `Cordis` et `CordisKernel` déjà déclarés. **Garder 6.1.**
- `Sources/Cordis/Cordis.swift` : `hello()` du template → à supprimer.
- `Sources/CordisKernel/CordisKernel.swift` : vide → à remplacer par les fichiers du noyau.
- `Tests/CordisKernelTests/CordisKernelTests.swift` : vide.
- `Tests/CordisTests/CordisTests.swift` : test template, mais **la target `CordisTests` n'est pas déclarée dans `Package.swift`** → à ajouter.
- Pas de target de démo → ajouter `CordisDemo` (executable, produit `cordis-demo`).
- Ajouter `.tvOS(.v17)` et `.watchOS(.v10)` si rien ne s'y oppose.

## 4. Structure cible

```
swift-cordis/
├── Package.swift
├── README.md
├── CLAUDE.md
├── Sources/
│   ├── CordisKernel/   Scope.swift, Service.swift, Registry.swift, Plugin.swift (Fork), Context.swift
│   ├── Cordis/         Exports.swift, ServicePlugin.swift
│   └── CordisDemo/     main.swift
├── Tests/
│   ├── CordisKernelTests/
│   └── CordisTests/
└── docs/  HANDOFF.md, reference/ (à supprimer une fois l'implémentation terminée)
```

Répartition : tout ce qui est dans `docs/reference/Sources/Cordis/` va dans `CordisKernel`,
sauf `ServicePlugin` (et ses extensions) qui va dans `Cordis`.

## 5. API publique visée

```swift
enum DatabaseKey: ServiceKey { typealias Value = any Database }

extension Context {                                   // mixin façon Cordis
    var database: (any Database)? { self[DatabaseKey.self] }
}

enum UserRepositoryPlugin: Plugin {
    static let inject = Inject(required: [DatabaseKey.self], optional: [LoggerKey.self])
    static func apply(_ ctx: Context, config: Void) async throws {
        let db = try ctx.require(DatabaseKey.self)
        try await ctx.provide(UserRepositoryKey.self, UserRepository(db: db))
    }
}

let app = Context.root()
await app.plugin(UserRepositoryPlugin.self)            // pending
let db = await app.plugin(SQLitePlugin.self, "main")   // → repo actif
await db.update("replica")                             // hot swap → repo redémarre
await db.dispose()                                     // → repo pending
```

Correspondance Cordis TS → Swift :

| Cordis | Swift |
|---|---|
| `ctx.plugin(fn, config)` | `await ctx.plugin(P.self, config)` → `PluginHandle<P>` |
| `inject: [...]` | `static let inject = Inject(required:, optional:)` |
| `ctx.provide('db')` | `try await ctx.provide(Key.self, value)` |
| `ctx.db` | extension `Context` + `self[Key.self]` |
| `ctx.on` / `ctx.emit` | typés : `ctx.on(E.self) { }`, `await ctx.emit(E())` |
| `ctx.effect` | `try await ctx.effect { …; return { teardown } }` |
| `ctx.on('dispose')` | `ctx.onDispose { }` |
| `ctx.isolate('db')` | `ctx.isolate(Key.self, label:)` |
| `fork.update` / `fork.dispose` | `handle.update(config)` / `handle.dispose()` |

## 6. Décisions de conception (à respecter)

1. **Un seul global actor `@CordisActor`** sérialise toute mutation du graphe (provide, withdraw, start, stop). Déterminisme > parallélisme ; le travail lourd vit dans les services.
2. **Clés typées `ServiceKey`** (style `EnvironmentKey`), jamais de chaînes. `Value` est en général un protocole pour permettre le hot swap.
3. **Générations** : chaque `provide` incrémente un compteur global. Un fork ne redémarre que si la génération d'un slot qu'il injecte a changé.
4. **Réconciliation ré-entrante sûre** : un fork en cours de réconciliation qui reçoit un nouveau changement le met en file (`needsReconcile`) au lieu de récurser. Les slots qu'un fork fournit lui-même sont ignorés pour ses propres dépendances.
5. **Échecs locaux** : si `apply` lève une erreur → rollback du scope du fork, statut `.failed`, événement `PluginFailed`. Le reste du graphe continue.
6. **Conflit de provider** : deux contextes différents ne peuvent pas fournir le même slot → `CordisError.serviceConflict`, le second plugin passe `.failed`.
7. **Teardown LIFO** et idempotent (`Disposable` à usage unique). Un `collect` sur un scope déjà disposé exécute le teardown immédiatement.
8. **Statuts awaités** (pas de `Task {}` fire-and-forget) pour garder un ordre d'événements déterministe et testable.

## 7. Invariants à couvrir par les tests (Swift Testing)

Les tests de `docs/reference/Tests/` sont le point de départ :

- [ ] Un consommateur reste `.pending` tant que sa dépendance requise manque, puis passe `.active`.
- [ ] Hot swap : ordre exact `withdraw:A, stop:A, start:B, provide:B`.
- [ ] Après `dispose` d'un provider, les listeners du consommateur ne reçoivent plus rien.
- [ ] Isolation : deux realms ont des instances distinctes ; le realm partagé n'en voit aucune.
- [ ] Conflit de provider rejeté, la valeur initiale est conservée.
- [ ] Plugin qui échoue → rollback + `PluginFailed` émis.
- [ ] `app.dispose()` démonte tout en ordre inverse.

À ajouter :
- [ ] Dépendance optionnelle : démarre sans, redémarre quand elle apparaît puis quand elle disparaît.
- [ ] Cascade A → B → C : retirer A remet B et C en pending ; le remettre réactive tout.
- [ ] Sous-plugins : disposer le parent dispose tout le sous-arbre.
- [ ] `update(config)` sur un plugin pending ne le démarre pas tant que ses deps manquent.
- [ ] Pas de redémarrage parasite quand un slot non injecté change.
- [ ] `ctx.effect` : teardown appelé exactement une fois.

## 8. Plan de travail suggéré

1. Compléter `Package.swift` (target `CordisTests`, target `CordisDemo`, plateformes) et l'arborescence de la section 4 ; supprimer le code du template.
2. Porter `docs/reference/Sources/Cordis/*` dans `CordisKernel`, `ServicePlugin` dans `Cordis`.
3. `swift build` — corriger les erreurs de concurrence Swift 6 (isolation, `Sendable`, closures `@CordisActor`).
4. Porter les tests, `swift test`, puis ajouter ceux de la section 7.
5. Faire tourner `swift run cordis-demo` et vérifier la sortie des 6 scénarios.
6. README : mention « portage non officiel inspiré de Cordis », tableau de correspondance, quickstart.
7. Supprimer `docs/reference/` une fois tout vert.

## 9. Points d'attention connus

- `Context.provide` capture `ObjectIdentifier(self)` comme owner : un contexte issu de `isolate()` est un objet distinct de son parent → vérifier que le withdraw retrouve bien le bon owner.
- `Fork.depends(on:)` résout les realms via `parent` : vérifier qu'un plugin chargé dans un contexte isolé réagit bien aux slots de son realm.
- `Registry.emit` itère sur un snapshot : un listener ajouté pendant un dispatch ne reçoit pas l'événement en cours (comportement voulu, à tester).
- `@CordisActor` sur les protocoles `Plugin` / `ServicePlugin` : vérifier que ça ne pose pas de souci avec les conformances depuis des `enum`.

## 10. Hors périmètre (plus tard)

Reconfiguration fine (diff de config), loader de plugins piloté par YAML/feature flags,
plugin d'observabilité (graphe de dépendances live), middleware d'événements, macros
(`@Plugin`, `@Service`), intégrations Vapor et SwiftUI.
