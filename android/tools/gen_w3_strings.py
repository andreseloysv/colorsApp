# Genera strings_w3.xml (es/de/en) desde Localizable.xcstrings de iOS.
# Uso: python3 build-android/gen_w3_strings.py  (desde la raíz del worktree)
import json, re, sys
from xml.sax.saxutils import escape

SRC = '/Users/andreseloyasanchezva/DEVELOP/colorsApp/ios/ColorsApp/Localizable.xcstrings'
OUT = {
    'es': 'android/app/src/main/res/values/strings_w3.xml',
    'de': 'android/app/src/main/res/values-de/strings_w3.xml',
    'en': 'android/app/src/main/res/values-en/strings_w3.xml',
}

# nombre de recurso -> clave exacta del catalogo iOS (la clave ES el texto es)
MAP = {
 # Feed: filtros y vacios
 'w3_filter_all': 'Todo',
 'w3_filter_saved': 'Guardadas',
 'w3_filter_unvoted': 'Por votar',
 'w3_feed_empty_all': 'Todavía no has analizado ninguna foto.',
 'w3_feed_empty_size': 'Ninguna foto se parece a una combinación de %lld colores.',
 'w3_feed_empty_saved': 'Aún no has guardado ninguna publicación. Toca «Guardar» para llevarla a tu jardín.',
 'w3_feed_empty_unvoted': 'Has votado todas tus fotos. ¡Gracias!',
 'w3_feed_empty_title': 'Tus fotos analizadas aparecen aquí',
 'w3_feed_empty_body': 'Analiza la ropa de una foto o escanea tu carrete: cada análisis se convierte en una publicación con su paleta y la combinación de Wada que más se parece. Todo ocurre en el teléfono.',
 'w3_analyze_photo': 'Analizar una foto',
 'w3_scan_library': 'Escanear carrete',
 # Dia / numeros / conteos
 'w3_day_combo': 'Combinación del día',
 'w3_random_combo': 'Combinación al azar',
 'w3_another_combo': 'Otra combinación',
 'w3_in_grid': 'En tu rejilla',
 'w3_locked_state': 'Bloqueada',
 'w3_one_color': '1 color',
 'w3_colors_count': '%lld colores',
 'w3_color_count_one_fmt': '%lld color',
 'w3_number_label': 'Nº %@',
 'w3_between': 'Entre %@ y %@',
 'w3_percent_int': '%lld\u00a0%%',
 'w3_percent_words': '%lld por ciento',
 'w3_delta_e': 'ΔE\u00a0%@',
 # Origen y metadatos
 'w3_source_library': 'Carrete',
 'w3_source_camera': 'Cámara',
 'w3_source_picked': 'Foto elegida',
 'w3_example': 'Ejemplo',
 'w3_whole_photo': 'Foto completa',
 'w3_one_person': '1 persona',
 'w3_people_count': '%lld personas',
 'w3_all_people_n': 'Todas las personas (%lld)',
 'w3_main_person_of': 'Persona principal de %lld',
 'w3_person_i_of_n': 'Persona %lld de %lld',
 'w3_all_people_with': 'Todas las personas (%lld) · %@',
 'w3_with_skin_excluded': '%@ · piel excluida',
 'w3_clothing_only': 'Solo ropa',
 'w3_whole_person': 'Persona completa',
 'w3_person': 'Persona',
 'w3_palette_garments': 'Paleta por prenda',
 'w3_palette_clothing': 'Paleta de la ropa',
 'w3_palette_person': 'Paleta de la persona',
 'w3_palette_photo': 'Paleta de la foto',
 'w3_outdated': 'Análisis antiguo',
 # Banner de escaneo
 'w3_scan_requesting': 'Pidiendo acceso a Fotos…',
 'w3_scan_fetching': 'Buscando las últimas fotos…',
 'w3_scan_analyzing_library': 'Analizando %lld/%lld fotos del carrete',
 'w3_scan_finished_banner': 'Escaneo terminado',
 'w3_scan_failed_banner': 'El escaneo no ha podido terminar',
 # Publicacion
 'w3_photo_unavailable': 'Foto no disponible',
 'w3_copy_hex': 'Copiar hex',
 'w3_no_colors': 'Sin colores',
 'w3_looks_like': 'Se parece a',
 'w3_no_combo_found': 'El motor no ha encontrado combinación',
 'w3_more_actions': 'Más acciones',
 'w3_open_in_extract': 'Abrir en Extraer',
 'w3_view_combo': 'Ver combinación',
 'w3_delete_from_feed': 'Borrar del Feed',
 'w3_yes_short': 'Sí',
 'w3_it_is': 'Es eso',
 'w3_yes_it_is': 'Sí, es eso',
 'w3_no_short': 'No',
 'w3_no_it_isnt': 'No, no es eso',
 'w3_save_short': 'Guardar',
 'w3_saved_short': 'Guardado',
 'w3_save_in_garden_label': 'Guardar en tu jardín',
 'w3_saved_in_garden_label': 'Guardado en tu jardín',
 'w3_copy_short': 'Copiar',
 'w3_copied_short': 'Copiado',
 'w3_copy_combo_hex': 'Copiar hex de la combinación',
 'w3_copy_palette_hex': 'Copiar hex de la paleta',
 'w3_share_card': 'Compartir tarjeta',
 'w3_saved_in_garden_toast': 'Guardado en el Jardín',
 'w3_removed_from_garden': 'Quitado del Jardín',
 'w3_thanks_hit': 'Gracias. Marcado como acierto',
 'w3_thanks_consider': 'Gracias. Lo tendremos en cuenta',
 'w3_copied_one': 'Copiado %@',
 'w3_copied_many': 'Copiados %lld hex',
 'w3_photo_unavailable_analysis': 'La foto de este análisis no está disponible',
 'w3_deleted_from_feed': 'Borrado del Feed',
 'w3_delete_dialog_title': '¿Borrar esta publicación del Feed?',
 'w3_delete_dialog_body': 'Se borra el análisis y su foto de la app. La foto original del carrete no se toca.',
 'w3_delete': 'Borrar',
 'w3_cancel': 'Cancelar',
 'w3_reanalyzing': 'Reanalizando…',
 'w3_copy_hex_hint': 'Copia el hex',
 'w3_open_combo_hint': 'Abre la combinación',
 'w3_color_i_of_n': 'Color %lld de %lld',
 # Extraer: captura
 'w3_extract_title': 'Analiza la ropa de una foto',
 'w3_extract_subtitle': 'Se procesa en el teléfono; nada sale del dispositivo.',
 'w3_pick_photo': 'Elegir foto',
 'w3_no_camera': 'No hay cámara en este dispositivo (simulador).',
 'w3_scan_library_200': 'Escanear carrete (200 fotos)',
 'w3_loading_photo': 'Cargando la foto…',
 'w3_preparing_photo': 'Preparando la foto…',
 'w3_analyzing_clothing': 'Analizando la ropa…',
 'w3_subject_crop': 'Recorte de sujeto',
 'w3_crop_off_full': 'Recorte desactivado · foto completa',
 'w3_mode_off': 'Desactivado',
 'w3_mode_all_people': 'Todas las personas',
 'w3_mode_largest': 'Persona principal',
 'w3_mode_selected': 'Persona elegida',
 'w3_region_clothing_lower': 'solo ropa',
 'w3_region_person_lower': 'persona completa',
 'w3_no_skin': 'sin piel',
 'w3_what_analysis_does': 'Qué hace el análisis',
 # Los 3 pasos NO estan en el catalogo: en iOS son literales String pasados a
 # Text(String) (verbatim), asi que iOS los ensena en espanol en de/en. Se
 # espeja ese comportamiento (ver OVERRIDE_ES abajo); no se inventa traduccion.
 'w3_step1_title': None,
 'w3_step1_body': None,
 'w3_step2_title': None,
 'w3_step2_body': None,
 'w3_step3_title': None,
 'w3_step3_body': None,
 # Resultado
 'w3_result': 'Resultado',
 'w3_banner_updated': 'Actualizado con el motor nuevo',
 'w3_banner_recalculated': 'Recalculado con el motor actual',
 'w3_voted_person_note': 'Ya has votado este resultado: para usar otra persona, analiza la foto de nuevo.',
 'w3_colors_by_garment': 'Colores por prenda',
 'w3_colors_clothing': 'Colores de la ropa',
 'w3_colors_photo': 'Colores de la foto',
 'w3_whole_photo_lower': 'foto completa',
 'w3_one_garment': '1 prenda',
 'w3_garments_count': '%lld prendas',
 'w3_of_the_photo': '%@ de la foto',
 'w3_region_upper': 'Parte de arriba',
 'w3_region_lower': 'Parte de abajo',
 'w3_region_whole': 'Prenda entera',
 'w3_region_garment': 'Prenda',
 'w3_region_upper_short': 'Arriba',
 'w3_region_lower_short': 'Abajo',
 'w3_score_better': 'Score %@ (menor es mejor)',
 'w3_is_this_combo': '¿Es esta la combinación?',
 'w3_thanks_hit_period': 'Gracias. Marcado como acierto.',
 'w3_thanks_miss': 'Gracias. Marcado como fallo; nos sirve para mejorar el motor.',
 'w3_not_in_grid_yet': 'Todavía no está en tu rejilla',
 'w3_unlock': 'Desbloquear',
 'w3_unlocked_now': 'Desbloqueada: ya está en tu rejilla.',
 'w3_already_in_grid': 'Ya en tu rejilla.',
 'w3_also_looks_like': 'También se parece a',
 'w3_no_combo_engine': 'El motor no ha encontrado ninguna combinación.',
 'w3_save_in_garden_btn': 'Guardar en el jardín',
 'w3_saved_in_garden_btn': 'Guardado en el jardín',
 'w3_copied_btn': 'Copiados',
 'w3_view_layers': 'Ver capas',
 'w3_preparing_card': 'Preparando la tarjeta…',
 'w3_no_result': 'Sin resultado',
 'w3_technical_footer': 'Motor %@ · diccionario %@ · %lld ms (Vision %lld · máscara %lld · motor %lld)',
 'w3_view_mask': 'Ver máscara',
 'w3_hide_mask': 'Ocultar máscara',
 'w3_crop_off_short': 'Recorte desactivado',
 'w3_no_people_full': 'Sin personas · foto completa',
 'w3_all_fem': 'Todas',
 'w3_person_1_main': 'Persona 1, principal',
 'w3_person_n': 'Persona %lld',
 'w3_all_people_label': 'Todas las personas',
 'w3_color_n': 'Color %lld',
 # Aviso de la cadena (SubjectExplanation.notice, subconjunto con los datos del contrato Android)
 'w3_notice_vision_unavailable': 'Vision no disponible: foto completa',
 'w3_notice_crop_off': 'Recorte desactivado: foto completa',
 'w3_notice_no_person': 'Sin persona: foto completa',
 'w3_notice_skin_guard': 'prenda parecida a la piel: no se excluyó',
 'w3_notice_skin_excluded': 'piel excluida',
 'w3_notice_split_pose': 'personas separadas por su pose',
 'w3_notice_split_face': 'personas separadas por su cara',
 'w3_notice_small_person': 'recorte demasiado pequeño: persona completa',
 'w3_notice_person_too_small': 'persona demasiado pequeña: foto completa',
 'w3_notice_garment_regions': 'un color por prenda',
 'w3_notice_head_cut_no_pose': 'sin la cabeza (sin pose)',
 'w3_notice_head_cut_incomplete': 'sin la cabeza (pose incompleta)',
 'w3_notice_silhouette': 'silueta del cuerpo',
 'w3_notice_skin_small_face': 'cara pequeña: piel sin excluir',
 'w3_notice_skin_no_face': 'sin cara visible: piel sin excluir',
 'w3_notice_detail_layers': '«Ver capas» explica cada paso.',
 'w3_step_none': 'Sin máscara',
 'w3_step_no_people': 'Sin personas',
 'w3_step_pose_regions': 'Regiones de la pose',
 'w3_step_head_cut': 'Recorte de cabeza',
 'w3_step_whole_person': 'Respaldo: persona completa',
 'w3_step_skin_excluded': 'Piel excluida',
 'w3_step_skin_guard': 'Salvaguarda de piel',
 'w3_step_vision_unavailable': 'Vision no disponible',
 'w3_step_garment_regions': 'Regiones de prenda (arriba / abajo)',
 'w3_step_split_pose': 'Personas separadas por su pose',
 'w3_step_split_face': 'Personas separadas por su cara',
 'w3_step_phantom': 'Siluetas sin cuerpo descartadas (%lld)',
 # Errores (ErrorText, subconjunto Android)
 'w3_error_unreadable': 'Imagen ilegible.',
 'w3_error_empty_image': 'La imagen está vacía.',
 'w3_error_engine': 'El motor de color devolvió el error %d.',
 'w3_error_buffer': 'Buffer de imagen corto (%lld de %lld bytes).',
 'w3_error_mask': 'Máscara corta (%lld de %lld bytes).',
 'w3_error_scan_not_implemented': 'El escaneo del carrete llega en la próxima build.',
 'w3_error_scan_cancelled': 'Escaneo cancelado.',
 # Onboarding del escaneo
 'w3_scan_intro_title': 'Tus últimas %lld fotos, en color',
 'w3_scan_intro_body': '%@ analiza en el propio teléfono las últimas %lld fotos del carrete y busca en la ropa de cada una la combinación de Sanzo Wada más parecida. Ninguna foto sale del dispositivo; solo se guardan los colores.',
 'w3_badge_no_network': 'Sin red',
 'w3_badge_no_account': 'Sin cuenta',
 'w3_badge_on_phone': 'En el teléfono',
 'w3_scan_now': 'Escanear ahora',
 'w3_not_now': 'Ahora no',
 'w3_scan_later_note': 'Puedes hacerlo más tarde desde Extraer, la Rejilla o tu Jardín.',
 'w3_scanning_library': 'Escaneando el carrete',
 'w3_scanning': 'Escaneando',
 'w3_library_section': 'Carrete',
 'w3_phase_preparing': 'Preparando…',
 'w3_phase_analyzing': 'Analizando %lld/%lld',
 'w3_phase_done': 'Listo',
 'w3_phase_error': 'Error',
 'w3_unlocked_one_combo': '1 combinación desbloqueada',
 'w3_unlocked_many_combos': '%lld combinaciones desbloqueadas',
 'w3_skipped_icloud': '%lld omitidas (solo en iCloud o no legibles)',
 'w3_scan_on_phone_note': 'Todo ocurre en el teléfono: puedes seguir usando la app.',
 'w3_limited_title': 'Acceso limitado a Fotos',
 'w3_limited_body': 'Solo podemos ver las fotos que elijas. Selecciona hasta %lld y las analizamos igual, en el propio teléfono.',
 'w3_pick_photos': 'Elegir fotos',
 'w3_denied_title': 'Sin acceso a Fotos',
 'w3_denied_body': 'Para escanear el carrete, permite el acceso a Fotos en Ajustes > %@. Las fotos se analizan solo en el teléfono.',
 'w3_open_settings': 'Abrir Ajustes',
 'w3_retry': 'Reintentar',
 'w3_scan_failed_title': 'El escaneo no ha terminado',
 # Wrapped
 'w3_wrapped_section': 'Escaneo del carrete',
 'w3_wrapped_title': 'Tu carrete en color',
 'w3_photo_analyzed_one': 'foto analizada',
 'w3_photos_analyzed_many': 'fotos analizadas',
 'w3_stats_analyzed': '%lld fotos analizadas',
 'w3_stats_skipped': '%lld omitidas',
 'w3_stats_failed': '%lld fallidas',
 'w3_duration_seconds': '%@ s',
 'w3_duration_minutes': '%lld min %lld s',
 'w3_wrapped_empty_title': 'No había fotos que analizar',
 'w3_wrapped_empty_body': 'Haz fotos de lo que llevas puesto o elige algunas del carrete y vuelve a intentarlo.',
 'w3_signature_color': 'Tu color firma',
 'w3_in_one_photo': 'en 1 foto',
 'w3_in_n_photos': 'en %lld fotos',
 'w3_your_5_colors': 'Tus 5 colores',
 'w3_no_unlock_reason': 'Ninguna foto se parecía lo bastante a una combinación de Wada (resultados ambiguos o lejanos no desbloquean).',
 'w3_and_more_in_grid': 'y %lld más en la rejilla',
 'w3_most_repeated': 'Las que más se repiten',
 'w3_one_photo': '1 foto',
 'w3_n_photos': '%lld fotos',
 'w3_counter_label': 'combinaciones de Sanzo Wada en tu rejilla',
 'w3_view_grid': 'Ver rejilla',
 'w3_combo_accessibility': 'Combinación %@, %@',
 # Tarjeta
 'w3_share_post_format': 'Publicación 4:5',
 'w3_share_story_format': 'Historia 9:16',
 'w3_no_combo': 'Sin combinación',
 'w3_analyzed_on_phone': 'Analizado en el teléfono',
 'w3_wada_number': 'Wada %@',
 'w3_brand_wada': '%@ · Wada %@',
 'w3_share_pixels_light': '%@ px · siempre en claro',
 'w3_share_card_preview': 'Vista previa de la tarjeta',
 'w3_share_send': 'Compartir',
 'w3_close': 'Cerrar',
 # Explicacion del match (LayerStack.explanationCards; en Resultado va la del top-1)
 'w3_explain_terms': 'Ajuste %@ · cobertura %@ · penalización %@',
 'w3_explain_summary_score': 'Score %@ = ajuste %@ + cobertura %@ + penalización %@. ',
 'w3_explain_fit': 'Ajuste: de media, cada color de la foto está a %@ ΔE00 de su color más cercano de la combinación. ',
 'w3_explain_coverage': 'Cobertura: cada color de la combinación está, de media, a %@ ΔE00 del color más cercano de la foto. ',
 'w3_explain_hypothesis': 'Se supuso %@ (penalización %@). ',
 'w3_explain_no_correction': 'Sin corrección de luz. ',
 'w3_explain_wins': 'Gana por tener el score más bajo.',
 'w3_explain_gap': 'Queda a %@ de la primera.',
 'w3_exposure_part': 'exposición %@%@ EV',
 'w3_illuminant_part': '%@ sin balance de blancos',
 'w3_no_correction_photo': 'Sin corrección (la foto tal cual)',
 'w3_join_and': ' y ',
 'w3_light_a': 'luz A (tungsteno)',
 'w3_light_d50': 'luz D50 (día cálido)',
 'w3_light_d65': 'luz D65 (día)',
 'w3_light_d75': 'luz D75 (sombra, fría)',
 'w3_light_f2': 'luz F2 (fluorescente)',
 'w3_light_n': 'luz %lld',
}

# Textos que iOS ensena verbatim en espanol en los tres idiomas (fuera del
# catalogo): mismo texto en values/, values-de/ y values-en/.
OVERRIDE_ES = {
 'w3_step1_title': 'Recorta a la persona',
 'w3_step1_body': 'Vision separa a cada persona; el motor se queda con su ropa y quita la piel.',
 'w3_step2_title': 'Extrae los colores',
 'w3_step2_body': 'Hasta 5 colores con su peso y el nombre del color de Wada más cercano.',
 'w3_step3_title': 'Busca la combinación',
 'w3_step3_body': 'Las 3 combinaciones de Sanzo Wada más parecidas, de las 348.',
}

cat = json.load(open(SRC, encoding='utf-8'))['strings']

def loc(entry, lang):
    if entry is None: return None
    l = entry.get('localizations', {}).get(lang)
    if not l: return None
    if 'stringUnit' in l: return l['stringUnit']['value']
    return None

SPEC = re.compile(r'%(\d+)\$(lld|ld|d|@)|%(lld|ld|d|@)|%%')

def convert(value, key):
    # Tipos por orden de aparicion en la CLAVE (es): da el tipo de cada posicional.
    types = []
    for m in SPEC.finditer(key):
        if m.group(0) == '%%': continue
        t = m.group(2) or m.group(3)
        types.append(t)
    out = []
    auto = 0
    i = 0
    for m in SPEC.finditer(value):
        out.append(value[i:m.start()])
        if m.group(0) == '%%':
            out.append('%%'); i = m.end(); continue
        pos = int(m.group(1)) if m.group(1) else auto + 1
        if not m.group(1): auto += 1
        t = types[pos - 1] if pos - 1 < len(types) else (m.group(2) or m.group(3) or '@')
        conv = 's' if t == '@' else 'd'
        out.append(f'%{pos}${conv}')
        i = m.end()
    out.append(value[i:])
    return ''.join(out)

missing = []
tables = {lang: [] for lang in OUT}
for res, key in MAP.items():
    if key is None:
        v = OVERRIDE_ES[res].replace("'", "\\'")
        for lang in OUT:
            tables[lang].append((res, escape(v)))
        continue
    entry = cat.get(key)
    if entry is None:
        missing.append((res, key)); continue
    for lang in OUT:
        v = key if lang == 'es' else (loc(entry, lang) or loc(entry, 'es') or key)
        v = convert(v, key).replace("'", "\\'").replace('"', '\\"')
        tables[lang].append((res, escape(v, {'"': '&quot;'}).replace('\\&quot;', '\\"')))

if missing:
    print('CLAVES AUSENTES:')
    for r, k in missing: print(' ', r, repr(k))
    sys.exit(1)

header = ('<?xml version="1.0" encoding="utf-8"?>\n'
          '<!-- Carril W3 (Feed, Extraer, Resultado, Tarjeta, Wrapped): textos EXACTOS de\n'
          '     ios/ColorsApp/Localizable.xcstrings (es = la clave; de/en = su localizacion).\n'
          '     Generado con build-android/gen_w3_strings.py; no editar a mano sin cotejar. -->\n')
for lang, path in OUT.items():
    body = ''.join(f'    <string name="{r}">{v}</string>\n' for r, v in tables[lang])
    open(path, 'w', encoding='utf-8').write(header + '<resources>\n' + body + '</resources>\n')
    print(path, len(tables[lang]), 'strings')
