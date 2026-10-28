# Kit de Google Play — ChromaSol

Material de la ficha de Google Play de **ChromaSol** (`com.andreseloy.colorsapp`,
app de pago único, precio de referencia 2,99 USD), adaptado desde la ficha de
la App Store (`fastlane/metadata/`, `docs/APPSTORE.md`, `docs/PRIVACY.md`).
Todo está pensado para copiar y pegar en Play Console; los documentos con
respuestas de formularios se leen a la vez que se rellena cada pantalla.

## Qué hay en esta carpeta

| Fichero | Para qué sirve | Dónde va en Play Console |
|---|---|---|
| `listing/es-ES/`, `listing/de-DE/`, `listing/en-US/` | Textos de la ficha por idioma: `title.txt` (≤ 30), `short_description.txt` (≤ 80), `full_description.txt` (≤ 4000), `release_notes.txt` (≤ 500) | Ficha principal de Play Store, una por idioma; las notas de la versión, en la pantalla de la release |
| `listing/NOTES.md` | Qué se cambió respecto a iOS y **qué frases hay que confirmar contra la build de Android antes de enviar** | No se sube: es la lista de comprobación previa |
| `icon_512.png` | Icono de la ficha, 512 × 512, PNG de 32 bits (RGBA) | Ficha principal > Icono de la app |
| `feature_graphic.png` | Gráfico destacado, 1024 × 500, RGB sin alfa, sin marcos ni precio; sirve para los tres idiomas (solo lleva la marca y nombres propios) | Ficha principal > Gráfico de funciones |
| `icon_master.png` | Icono maestro actual (1024 × 1024), copia del icono de iOS; **marcador de posición** | No se sube: es la entrada de `tools/make_graphics.py` |
| `icon_exports/icon_*.png` | Copias del icono a 192/144/96/72/48 px por si el carril de Android las necesita | No se suben a la ficha (el icono adaptativo lo monta el proyecto `android/`) |
| `data_safety.md` | Respuestas del formulario «Seguridad de los datos»: no se recoge ni se comparte ningún dato | Contenido de la app > Seguridad de los datos |
| `content_rating.md` | Respuestas del cuestionario IARC de clasificación de contenido (todo «No») | Contenido de la app > Clasificación de contenido |
| `app_content.md` | Resto de declaraciones (anuncios, público objetivo, noticias, gobierno, finanzas, salud, eliminación de cuenta), categoría recomendada, contacto, precio y URL de privacidad | Contenido de la app + Configuración de la ficha |
| `site_changes.md` | Cambios exactos (es/de/en) para que la página pública de privacidad, hoy solo de iOS, cubra también Android | Se aplica en `docs/site/` del repo principal y se publica en el repo `colorsApp_public` antes de enviar |
| `tools/check_limits.py` | Comprueba límites de caracteres, términos de iOS prohibidos, menciones obligatorias y tamaño/modo de los PNG | Se ejecuta tras cada cambio de textos |
| `tools/make_graphics.py` | Regenera `icon_512.png`, `icon_exports/` y `feature_graphic.png` | Se ejecuta al cambiar el icono maestro o el gráfico |

**No incluye capturas de pantalla de Android** (Play exige al menos 2 de
teléfono por ficha): las tiene que producir el carril A desde la build real
de Android. Las capturas de iPhone de `fastlane/screenshots/` no se deben
reutilizar para Android.

## El icono: marcador de posición y cómo cambiarlo

El icono que le gusta al propietario aún no existe (se está haciendo un
icono 3D nuevo en otro carril). Mientras tanto `icon_master.png` es una
copia del icono actual de iOS (1024 × 1024) y `icon_512.png` se genera
desde él.

Cuando llegue el icono nuevo:

1. Guardar el maestro nuevo como `docs/play/icon_master.png`
   (cuadrado, 1024 × 1024; el script acepta cualquier cuadrado ≥ 512 px).
2. Ejecutar `python3 docs/play/tools/make_graphics.py`: regenera
   `icon_512.png` y `icon_exports/` automáticamente.
3. Entregar también el mismo maestro al carril A para el icono adaptativo
   dentro de la app (`android/`); el gráfico destacado no usa el icono y
   no hay que tocarlo.

## Comprobar el kit

Desde la raíz del repo:

```sh
python3 docs/play/tools/make_graphics.py   # regenera y verifica los PNG
python3 docs/play/tools/check_limits.py    # límites y reglas de los textos
```

Ambos scripts necesitan Python 3 con Pillow (presente en el `python3` de
Homebrew de esta máquina). `check_limits.py` debe terminar en
`RESULT: PASS`; cualquier `FAIL` indica el fichero y el motivo. El gráfico
destacado usa los colores reales de las combinaciones de Wada de
`data/wada/dictionary.json` y las fuentes de la app en
`ios/ColorsApp/Resources/Fonts/`, así que no hay que descargar nada.

## Orden para rellenar Play Console

Solo el propietario puede hacer los pasos de cuenta (crear la app,
identidad, perfil de pagos, firmar y enviar). Este orden evita que la
consola bloquee pantallas por dependencias entre formularios:

1. **Crear la app** en Play Console: nombre ChromaSol, idioma
   predeterminado **español (es-ES)**, app (no juego), de pago.
2. **Subir el AAB** del carril A a una pista de prueba interna. Sin una
   build subida no se pueden cerrar varias declaraciones, y así se
   comprueba el `applicationId` (`com.andreseloy.colorsapp`).
3. **Política de privacidad publicada**: aplicar primero los cambios de
   `site_changes.md` y verificar que
   `https://andreseloysv.github.io/colorsApp_public/privacy.en.html`
   responde y ya menciona Android. Sin esto, la URL no debe darse.
4. **Contenido de la app**, en este orden:
   - Política de privacidad (la URL anterior).
   - Anuncios: No. Acceso a la app: sin acceso especial
     (`app_content.md`).
   - Seguridad de los datos con `data_safety.md`, pero solo **después**
     de comprobar sobre el AAB final que el manifiesto fusionado no trae
     `android.permission.INTERNET` ni SDK de analíticas/descargas.
   - Clasificación de contenido (IARC) con `content_rating.md`
     (correo `andreslaley@msn.com`).
   - Público objetivo: 13 años o más (`app_content.md`).
   - Noticias: No; gobierno: No; funciones financieras: No; salud: No;
     eliminación de cuenta: no aplica (sin cuentas).
5. **Configuración de la ficha**: categoría **Arte y diseño** (motivos en
   `app_content.md`), correo de contacto `andreslaley@msn.com`.
   Ojo: la web de privacidad publica hoy otro buzón
   (`andreseloysv@gmail.com`); decidir si se unifican (ver
   `app_content.md` y `site_changes.md`).
6. **Ficha principal, por idioma** (es-ES, de-DE, en-US): pegar
   `title.txt`, `short_description.txt` y `full_description.txt` de
   `listing/<idioma>/`; subir el mismo `icon_512.png` y
   `feature_graphic.png` en los tres; añadir las capturas de Android del
   carril A. Antes de pegar, revisar `listing/NOTES.md` y borrar las
   líneas de funciones que la build final no tenga.
7. **Precio y países**: precio base 2,99 USD (revisar los importes
   convertidos país a país) y disponibilidad en todos los países, salvo
   decisión contraria del propietario.
8. **Release de producción**: subir el AAB definitivo, pegar
   `release_notes.txt` de cada idioma en las notas de la versión y enviar
   a revisión. La primera revisión de una cuenta/app nueva puede tardar
   varios días.

## Antes de enviar (comprobación final)

- [ ] `python3 docs/play/tools/check_limits.py` termina en `RESULT: PASS`.
- [ ] Las líneas «pendientes de confirmar» de `listing/NOTES.md`
      contrastadas con el AAB final; borradas las que no se cumplan.
- [ ] Manifiesto fusionado del AAB sin `android.permission.INTERNET`
      (base de `data_safety.md` y de varios textos de la ficha).
- [ ] Página de privacidad actualizada según `site_changes.md` y en
      línea en la URL dada a la consola.
- [ ] Capturas de Android reales (carril A) subidas en los tres idiomas.
- [ ] Icono: o se acepta el provisional de iOS, o está el maestro nuevo
      en `icon_master.png` y se regeneraron los PNG.
