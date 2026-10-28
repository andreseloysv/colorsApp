# Cambios necesarios en la página pública de privacidad

Comprobación hecha sobre el checkout principal (`docs/site/privacy.html`,
`privacy.en.html`, `privacy.es.html`) y sobre la URL que exige Play:
`https://andreseloysv.github.io/colorsApp_public/privacy.en.html`
(consultada el 2026-10-28: responde 200 y sirve el mismo texto que el
fichero local, «ChromaSol for iOS, version 1.0.0», «on your iPhone»).

**Veredicto: el texto actual es solo de iOS.** Dice «ChromaSol para iOS»,
«en tu iPhone» y da la ruta de ajustes de iOS. El fondo (sin recogida de
datos, todo en el dispositivo) vale igual para Android, pero tal como está
redactada, la página no cubre la versión de Android y Play exige que la
política enlazada corresponda a la app enviada.

Dónde se aplica el cambio (no en este carril): las páginas se editan en
`docs/site/` del repo principal y se copian al repo público
`~/DEVELOP/colorsApp_public` (ver `docs/APPSTORE.md` §9c); el repo público
no se edita a mano. Las URL no cambian, así que la ficha de la App Store
sigue enlazando a las mismas direcciones. Hay que aplicar los cambios y
publicarlos **antes** de enviar la app de Android a revisión, y la misma
actualización debería reflejarse en `docs/PRIVACY.md` (hoy solo es/en).

A continuación, los cambios exactos, frase actual → frase nueva, por idioma.
La fecha de entrada en vigor se sustituye por el día en que se publiquen
estos cambios (indicado como `‹fecha›`).

## Español — `privacy.es.html`

1. Metadescripción (`<meta name="description">`):
   - Ahora: «ChromaSol no recoge ningún dato personal. Las fotos se analizan solo en el iPhone.»
   - Nuevo: «ChromaSol no recoge ningún dato personal. Las fotos se analizan solo en tu dispositivo.»
2. Línea de cabecera:
   - Ahora: «ChromaSol para iOS, versión 1.0.0 · En vigor desde el 22 de septiembre de 2026»
   - Nuevo: «ChromaSol para iOS y Android · En vigor desde el ‹fecha›»
3. Viñeta del análisis:
   - Ahora: «Todo el análisis ocurre en tu iPhone. Ninguna foto, ni ninguna parte de una foto, sale del dispositivo.»
   - Nuevo: «Todo el análisis ocurre en tu dispositivo. Ninguna foto, ni ninguna parte de una foto, sale del dispositivo.»
4. Viñeta de permisos:
   - Ahora: «Solo accede a las fotos que eliges con el selector o la cámara, o al carrete si concedes ese permiso. Puedes retirarlo en Ajustes > Privacidad y seguridad > Fotos.»
   - Nuevo: «Solo accede a las fotos que eliges con el selector o la cámara, o a tu galería si concedes ese permiso. Puedes retirarlo cuando quieras: en iOS, en Ajustes > Privacidad y seguridad > Fotos; en Android, en Ajustes > Aplicaciones > ChromaSol > Permisos.»
5. Añadir tras el párrafo de «Datos que no se recogen»:
   - Nuevo: «Si compraste la app, el pago lo procesa la tienda (Apple o Google). No recibimos los datos de tu tarjeta ni de tu método de pago.»

El resto (resumen, base de datos local, diagnóstico opcional, menores y
contacto) no menciona iOS y puede quedarse igual.

## Deutsch — `privacy.html`

1. Metadescripción (`<meta name="description">`):
   - Jetzt: «ChromaSol erhebt keine personenbezogenen Daten. Fotos werden nur auf dem iPhone verarbeitet.»
   - Neu: «ChromaSol erhebt keine personenbezogenen Daten. Fotos werden nur auf deinem Gerät verarbeitet.»
2. Kopfzeile:
   - Jetzt: «ChromaSol für iOS, Version 1.0.0 · Gültig ab 22. September 2026»
   - Neu: «ChromaSol für iOS und Android · Gültig ab ‹fecha›»
3. Aufzählungspunkt zur Analyse:
   - Jetzt: «Die gesamte Analyse läuft auf deinem iPhone. Kein Foto und kein Teil eines Fotos verlässt das Gerät.»
   - Neu: «Die gesamte Analyse läuft auf deinem Gerät. Kein Foto und kein Teil eines Fotos verlässt das Gerät.»
4. Aufzählungspunkt zu den Berechtigungen:
   - Jetzt: «Sie greift nur auf die Fotos zu, die du auswählst, oder auf die Mediathek, wenn du es erlaubst. Du kannst das jederzeit unter Einstellungen > Datenschutz & Sicherheit > Fotos widerrufen.»
   - Neu: «Sie greift nur auf die Fotos zu, die du auswählst, oder auf deine Galerie, wenn du es erlaubst. Du kannst das jederzeit widerrufen: unter iOS in Einstellungen > Datenschutz & Sicherheit > Fotos, unter Android in Einstellungen > Apps > ChromaSol > Berechtigungen.»
5. Nach dem Absatz «Daten, die nicht erhoben werden» einfügen:
   - Neu: «Wenn du die App gekauft hast, wickelt der Store (Apple oder Google) die Zahlung ab. Wir erhalten keine Daten deiner Karte oder deiner Zahlungsart.»

El resto («Kurz gefasst», base de datos local, «Optionale Diagnose»,
«Kinder» y «Kontakt») no menciona iOS y puede quedarse igual.

## English — `privacy.en.html` (la URL que se da a Play)

1. Meta description:
   - Now: "ChromaSol collects no personal data. Photos are analyzed on the iPhone only."
   - New: "ChromaSol collects no personal data. Photos are analyzed on your device only."
2. Header line:
   - Now: "ChromaSol for iOS, version 1.0.0 · Effective 22 September 2026"
   - New: "ChromaSol for iOS and Android · Effective ‹fecha›"
3. Analysis bullet:
   - Now: "All analysis happens on your iPhone. No photo, and no part of a photo, ever leaves the device."
   - New: "All analysis happens on your device. No photo, and no part of a photo, ever leaves the device."
4. Permissions bullet:
   - Now: "It only accesses photos you pick with the picker or camera, or your library if you grant that permission. You can revoke it in Settings > Privacy & Security > Photos."
   - New: "It only accesses photos you pick with the picker or camera, or your gallery if you grant that permission. You can revoke it at any time: on iOS in Settings > Privacy & Security > Photos, on Android in Settings > Apps > ChromaSol > Permissions."
5. Add after the "Data we do not collect" paragraph:
   - New: "If you bought the app, payment is processed by the store (Apple or Google). We do not receive your card or payment-method details."

The rest (summary, local database, optional diagnostics, children and
contact) does not mention iOS and can stay as it is.

## Dos puntos que dependen de decisiones aún abiertas

1. **Diagnóstico opcional.** La frase «En Ajustes > Exportar diagnóstico…»
   describe una función de la versión de iOS. Si el port de Android (carril
   A) no la incluye en su primera versión, esa frase no será cierta para
   Android y conviene sustituir el apartado, en los tres idiomas, por la
   versión genérica:
   - es: «Si la versión de tu dispositivo ofrece exportar un diagnóstico en los ajustes de la app, ese archivo solo contiene datos técnicos (versiones, tiempos y resultados numéricos; nunca fotos), solo se crea si lo pides y solo llega a quien tú se lo envíes.»
   - de: «Wenn die Version auf deinem Gerät in den App-Einstellungen einen Diagnoseexport anbietet, enthält diese Datei nur technische Daten (Versionen, Zeiten und Zahlen; niemals Fotos), entsteht nur auf deine Anfrage und geht nur an die Person, der du sie schickst.»
   - en: "If the version on your device offers a diagnostics export in the app settings, that file only contains technical data (versions, timings and numbers; never photos), is only created when you ask, and only reaches whomever you send it to."
   Si Android sí incluye la exportación, el texto actual vale sin cambios.
2. **Correo de contacto.** La página publica `andreseloysv@gmail.com`; el
   correo pedido para la ficha de Play es `andreslaley@msn.com` (ver
   `app_content.md`). Si el propietario quiere un único buzón público, hay
   que cambiar el `<a href="mailto:…">` y el texto visible en las tres
   páginas de privacidad (y en las de soporte) por el que se decida. Si se
   mantienen los dos, no hay que tocar nada aquí.

## Páginas vecinas del mismo sitio (fuera del alcance estricto de Play)

Play solo exige la URL de privacidad, pero las páginas enlazadas desde
ella también hablan solo de iOS. Para que el sitio no se contradiga el
día del lanzamiento de Android, conviene el mismo repaso en:

| Página | Frases solo de iOS detectadas | Cambio |
|---|---|---|
| `index.html` / `index.es.html` / `index.en.html` | «según el idioma del iPhone» / «following the iPhone's language» / «je nach Sprache des iPhones» | «según el idioma del sistema» / "following your device's system language" / «je nach Systemsprache deines Geräts» |
| `index.*.html` | La descripción no menciona Android | Añadir, al publicar, que también está en Android (una frase; sin enlaces a tiendas hasta que la ficha de Play sea pública) |
| `support.html` / `support.es.html` / `support.en.html` | «ChromaSol für iOS / para iOS / for iOS, Version/versión/version 1.0.0» en la cabecera | «ChromaSol para iOS y Android» (equivalentes de/en, como en privacidad) |
| `support.*.html` | «Der Ausschnitt nutzt Apple Vision…» / "The crop uses Apple Vision…" | Reescribir sin nombrar la tecnología de Apple, p. ej. es: «La app busca personas en la foto en el propio dispositivo; si no reconoce a nadie, analiza la foto entera.» (equivalentes de/en) |
| `support.*.html` | «Welche Sprachen?… je nach Sprache des iPhones» (equivalentes es/en con «iPhone») | Mismo cambio que en el índice: idioma del sistema del dispositivo |
| `docs/PRIVACY.md` (fuente es/en en el repo) | «en tu iPhone», «Ajustes de iOS», «on your iPhone», «iOS Settings» | Los mismos cambios 1–5 de arriba en es y en; la versión alemana solo existe en el HTML |
