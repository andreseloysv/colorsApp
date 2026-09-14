# Post-MVP: servidor, cuentas, roles y sync offline-first en iOS (investigación 2026-09-14)

## 1. Restricciones de Apple que fijan el orden de las fases

Tabla oficial "Supported capabilities (iOS)" (leída del HTML crudo, columna "Apple Developer" = Apple ID gratuito): **NO disponibles** sin pagar: iCloud (CloudKit, documents, key-value), Push Notifications, Sign in with Apple (solo ADP, ni siquiera Enterprise), Associated Domains, App Attest. **Sí disponibles**: App Groups, Background Modes, Data Protection, Keychain Sharing, HealthKit, HomeKit, Maps. Xcode lo dice literalmente: "Personal development teams ... do not support the Push Notifications and iCloud capabilities".

Personal team: máximo 10 App IDs, 3 dispositivos, y perfiles de aprovisionamiento que **caducan a los 7 días**; TestFlight y App Store Connect solo con Apple Developer Program (99 USD/año). Dos iPhones caben en el límite de 3 dispositivos. El iPhone necesita Developer Mode (Ajustes > Privacidad y seguridad; introducido en iOS 16 según fuentes secundarias). AltStore/SideStore no amplían los límites (3 apps activas, 7 días, 10 App IDs/semana); SideStore refresca en el propio dispositivo sin Mac.

App Review 4.8: Sign in with Apple **no es obligatorio** si "your app exclusively uses your company's own account setup and sign-in systems". Añadir Google/Facebook login sí lo obligaría. Validar tokens de Sign in with Apple en servidor exige un `client_secret` JWT firmado con una clave privada creada en la cuenta de desarrollador (ADP).

Conclusión: backend propio, login por email (magic link/OTP), roles y sync se construyen y prueban en los dos iPhones **sin pagar**. Esperan: CloudKit, APNs, Sign in with Apple, TestFlight.

## 2. Servidor: C frente a alternativas

| Lib | Licencia | Último release | Nota |
|---|---|---|---|
| libmicrohttpd | LGPL-2.1+ (eCos si sin TLS) | 1.0.10, 2026-08-07 | Solo HTTP/1.1; sin router/JSON/auth |
| civetweb | MIT | v1.16, 2023-04-10 (commits 2026-08) | Embebible, TLS OpenSSL, Lua, WebSocket |
| Mongoose | GPLv2 **o** comercial | 7.23, 2026-08-12 | Orientado a embebido/IoT; GPL en tu código servidor |
| h2o | MIT | ya no etiqueta versiones (2019→) | Servidor/proxy, no framework de app |
| facil.io | MIT | 0.7.6, 2022-02-19; master "likely broken" | Riesgo de mantenimiento |
| Kore | ISC | 4.3.0, 2026-09-02 | `brew install kore`, libpq async, ACME, privsep, Python/Lua |

Coste honesto (no medible con fuentes; juicio): en C hay que ensamblar JSON (cJSON/jansson), JWT (libjwt 3.6.1, MPL-2.0, requiere OpenSSL/GnuTLS/mbedTLS + jansson/json-c), DB (sqlite3/libpq), migraciones, validación y TLS a mano; en Go/Rust/TypeScript o Swift server eso viene resuelto. Con Swift 6.3 ya instalado, **Vapor 4.122.1 (MIT, Swift 6.0+)** o **Hummingbird 2.26.0 (Apache-2.0, Swift 6.1+)** permiten compartir modelos/DTOs con la app y enlazar el motor C como target SPM. Si el usuario insiste en C: Kore (ISC, activo, PostgreSQL) o civetweb (MIT) embebido; evitar Mongoose (GPL) y facil.io.

## 3. Sync offline-first

Patrón propio (recomendado para este volumen: 348 registros fijos + paletas/colecciones/favoritos/progreso): tabla `outbox` local con `mutationId` secuencial por cliente e idempotencia; `POST /push` aplica mutaciones y devuelve `lastMutationId`; `GET /pull?since=<cursor>` devuelve delta con `updatedAt`/`deletedAt` (soft delete) y nuevo cursor; LWW por `updatedAt` para datos de usuario, servidor manda en curado. Es exactamente el modelo documentado por Replicache (push/pull, cookie, lastMutationID, rebase de mutaciones pendientes). IDs: UUIDv7 (RFC 9562, mayo 2024, 48 bits de ms Unix + aleatorio).

Alternativas listas:
- **PowerSync**: SDK Swift 1.16.1 Apache-2.0, iOS 15+, integra GRDB 7.11; servicio FSL-1.1-ALv2 (pasa a Apache-2.0 a los 2 años), self-host en Docker pero exige MongoDB o Postgres 14+ como storage de buckets; autentica con JWT (HS256 dev, RS256/EdDSA/ES256 vía JWKS; `sub`=userId, `aud`, `exp` ≤24 h). Cloud free: 2 GB sync/mes, 500 MB, 50 clientes concurrentes, **desactivado tras 1 semana inactivo**.
- **ElectricSQL** (Apache-2.0): solo read-path, clientes oficiales TypeScript y Elixir; clientes Swift de terceros con 2 y 20 estrellas.
- **Zero** (Apache-2.0): React/SolidJS/React Native + Postgres + zero-cache; sin Swift. **Replicache**: repo archivado 2026-06-10, solo JS.

## 4. Persistencia local

**GRDB.swift 7.11.1** (MIT, 2026-06-18; iOS 13+, Swift 6.1+/Xcode 16.3+): SQL real, migraciones, ValueObservation, WAL, FTS, SQLCipher; es además la base de PowerSync. **SwiftData** (iOS 17+): con CloudKit prohíbe `@Attribute(.unique)`, obliga propiedades opcionales/con default y relaciones opcionales; rendimiento inferior (SQLite directo > Core Data > SwiftData) e inestabilidad en iOS 18 (fuente secundaria). **SQLite.swift 0.16.0** (MIT, 2026-03-08): válido pero sin observación ni migraciones integradas. Recomendación: GRDB, con columnas `id` UUIDv7, `updatedAt`, `deletedAt`, `rev`, `dirty`.

## 5. Auth y roles

JWT firmado por el servidor con claim `role` (`admin`|`user`); el servidor valida algoritmo por allowlist (nunca `none`), `iss`, `aud`, `exp` (RFC 8725) y **decide por rol en cada endpoint `/admin/*`**, nunca por el cliente. Proveedores gratuitos mientras no haya ADP:
- **Supabase**: 50 000 MAU, 500 MB, 2 proyectos, pausa tras 1 semana inactivo; magic links incluidos pero el email integrado solo permite **2 emails/hora** → configurar SMTP propio. SDK `supabase-swift` 2.55.2 MIT.
- **Firebase Auth**: 50 000 MAU, pero plan Spark limita a 3 000 DAU y **5 emails de sign-in link/día** sin tarjeta.
- **Clerk**: 50 000 MRU. **Auth0**: 25 000 MAU con passwordless.
- Propio: magic link/OTP por email + libjwt (C) o JWTKit (Vapor). Sign in with Apple se añade después de pagar.

## 6. Secuencia recomendada

Antes de pagar: (1) app local con GRDB y esquema ya sync-ready; (2) servidor (Swift/Kore) + Postgres/SQLite, `/auth` magic link, JWT con rol; (3) `/push` `/pull` + outbox en cliente, pruebas en los 2 iPhones re-firmando cada 7 días; (4) panel admin (web o endpoints) para curado. Después de pagar ADP: TestFlight, APNs (silent push para disparar pull), Sign in with Apple (si se añaden logins sociales), CloudKit solo si se quiere sustituir el backend (poco recomendable con roles admin).

---

## Findings (claim | confidence | URL)

1. Tabla oficial de capacidades iOS: iCloud (CloudKit/documents/KVS), Push Notifications, Sign in with Apple, Associated Domains y App Attest sin marca en la columna "Apple Developer" (gratuita); Sign in with Apple solo ADP. | verified | https://developer.apple.com/help/account/reference/supported-capabilities-ios/
2. App Groups, Background Modes, Data Protection, Keychain Sharing, HealthKit, HomeKit, Maps sí disponibles con cuenta gratuita. | verified | https://developer.apple.com/help/account/reference/supported-capabilities-ios/
3. Personal team: 10 App IDs, 3 dispositivos, perfiles caducan a 7 días; TestFlight/App Store Connect/Xcode Cloud solo ADP. | verified | https://developer.apple.com/support/compare-memberships/
4. Error literal de Xcode: "Personal development teams ... do not support the Push Notifications capability". | verified | https://developer.apple.com/forums/thread/718388
5. CloudKit: "verify that your Apple Developer Program membership is active"; activar CloudKit añade Push Notifications. | verified | https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app
6. Sign in with Apple token validation exige client_secret JWT con clave privada de la cuenta de desarrollador. | verified | https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens
7. Guideline 4.8: otro login no requerido si la app usa exclusivamente sistema de cuentas propio. | verified | https://developer.apple.com/app-store/review/guidelines/
8. Developer Mode requerido para ejecutar desde Xcode; se activa en Privacidad y seguridad. | verified | https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
9. Developer Mode introducido en iOS 16. | likely | https://docs.expo.dev/guides/ios-developer-mode/
10. AltStore: 3 apps sideloaded a la vez, expiran a 7 días, refresco en background con AltServer. | verified | https://faq.altstore.io/altstore-classic/your-altstore
11. SideStore: refresca en el dispositivo con VPN local; free Apple ID: 3 apps activas, 10 apps/semana, 7 días. | verified | https://docs.sidestore.io/docs/faq
12. libmicrohttpd LGPL-2.1+ (eCos si sin TLS), HTTP/1.1, varios modelos de hilos; último 1.0.10 (2026-08-07). | verified | https://www.gnu.org/software/libmicrohttpd/ y https://ftp.gnu.org/gnu/libmicrohttpd/
13. civetweb MIT, HTTPS OpenSSL, WebSocket, Lua, HTTP/2 experimental; último release v1.16 (2023-04-10), push 2026-08-01. | verified | https://github.com/civetweb/civetweb
14. Mongoose "GPLv2 or Commercial"; 7.23 (2026-08-12). | verified | https://github.com/cesanta/mongoose
15. h2o MIT, HTTP/1-2-3; dejó de etiquetar versiones. | verified | https://github.com/h2o/h2o/releases
16. facil.io MIT; último release 0.7.6 (2022-02-19); master "likely to be broken". | verified | https://github.com/boazsegev/facil.io
17. Kore ISC, 4.3.0 (2026-09-02), brew install kore, libpq async, ACME, privsep, Python/Lua. | verified | https://kore.io/ y https://kore.io/releases/4.3.0
18. Vapor MIT 4.122.1 (2026-08-25), Swift 6.0+; Hummingbird Apache-2.0 2.26.0 (2026-07-29), Swift 6.1+. | verified | https://github.com/vapor/vapor y https://github.com/hummingbird-project/hummingbird
19. libjwt MPL-2.0 v3.6.1; HS/RS/PS/ES/EdDSA; requiere jansson o json-c y OpenSSL 3/GnuTLS/mbedTLS. | verified | https://github.com/benmcollins/libjwt
20. C exige ensamblar más piezas que Go/Rust/TS/Swift server (coste mayor). | unverified | —
21. GRDB.swift MIT v7.11.1 (2026-06-18), iOS 13+, Swift 6.1+/Xcode 16.3+, migraciones, observación, WAL, FTS, SQLCipher. | verified | https://github.com/groue/GRDB.swift
22. SQLite.swift MIT 0.16.0 (2026-03-08). | verified | https://github.com/stephencelis/SQLite.swift/releases
23. SwiftData iOS 17+. | verified | https://developer.apple.com/documentation/swiftdata
24. SwiftData con CloudKit: sin @Attribute(.unique), propiedades opcionales/default, relaciones opcionales; rendimiento SQLite>CoreData>SwiftData; inestable en iOS 18. | likely | https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/
25. PowerSync Swift SDK Apache-2.0 1.16.1 (2026-08-31), iOS 15+, GRDB 7.11. | verified | https://github.com/powersync-ja/powersync-swift
26. PowerSync service FSL-1.1-ALv2; self-host requiere MongoDB o Postgres 14+ para buckets; JWT HS256 o JWKS; sub/aud/exp≤24h. | verified | https://github.com/powersync-ja/powersync-service ; https://docs.powersync.com/self-hosting/installation/powersync-service-setup ; https://docs.powersync.com/installation/authentication-setup/custom
27. PowerSync Cloud free: 2 GB/mes, 500 MB, 50 clientes concurrentes, desactivado tras 1 semana inactivo. | verified | https://www.powersync.com/pricing
28. ElectricSQL Apache-2.0, read-path only, clientes TS y Elixir; Swift solo terceros (electric-swift 2★, ElectricSync 20★). | verified | https://electric.ax/docs/intro ; https://github.com/casvandergun/electric-swift ; https://github.com/paulharter/ElectricSync
29. Zero Apache-2.0, React/SolidJS/React Native, Postgres + zero-cache. | verified | https://zero.rocicorp.dev/llms.txt ; https://zero.rocicorp.dev/docs/open-source
30. Replicache repo archivado 2026-06-10; JS/TS. Su doc describe push/pull, cookie, lastMutationID y rebase. | verified | https://github.com/rocicorp/replicache ; https://doc.replicache.dev/concepts/how-it-works
31. UUIDv7 en RFC 9562 (mayo 2024). | verified | https://www.rfc-editor.org/rfc/rfc9562.html
32. RFC 8725: allowlist de algoritmos, validar aud/iss, no confiar en claims. | verified | https://www.rfc-editor.org/rfc/rfc8725.html
33. Supabase free: 50 000 MAU, 500 MB, 2 proyectos, pausa tras 1 semana; email integrado 2 emails/hora; supabase-swift MIT 2.55.2. | verified | https://supabase.com/pricing ; https://supabase.com/docs/guides/auth/rate-limits ; https://github.com/supabase/supabase-swift
34. Firebase Auth 50K MAU gratis; Spark: 3 000 DAU y 5 emails de sign-in link/día. | verified | https://firebase.google.com/pricing ; https://firebase.google.com/docs/auth/limits
35. Clerk free 50 000 MRU; Auth0 free 25 000 MAU con passwordless. | verified | https://clerk.com/pricing ; https://auth0.com/pricing
