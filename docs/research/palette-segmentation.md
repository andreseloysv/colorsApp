# Investigación: extracción de paleta, segmentación de ropa y generador sintético

Fecha: 2026-09-14. Alcance: capas 2, 3 y 4 del motor descrito en CONTEXT.md §5, con la restricción de iPhone sin Apple Developer Program (§7) y el toolchain de §8.

## Resumen

### 1. Extracción de paleta on-device

- **MMCQ (median cut modificado, Leptonica `colorquant2.c`)**: parte de Heckbert 1982; histograma de 5 o 6 bits por canal; el 85 % de las divisiones se elige por población y el resto por población×volumen; corta el eje más largo "a mitad del lado mayor respecto a la mediana". No tiene ninguna fuente de aleatoriedad: es determinista y, al operar sobre un histograma, invariante al orden de los píxeles. Es lo que usaba color-thief (MIT); la v3 actual cuantiza en OKLCH.
- **k-means++**: el primer centro se elige uniformemente al azar y los siguientes con probabilidad ∝ D(x)²; garantía O(log k) "en expectativa sobre la aleatoriedad". Con semilla fija es reproducible run-a-run, pero **barajar píxeles cambia la semilla efectiva** → falla el test de invariancia de la capa 2 salvo que la inicialización sea determinista. sklearn `KMeans(init='k-means++', n_init='auto'→1, random_state=int)` y `fit(X, sample_weight=)` permiten pesos por píxel.
- **Octree** (Pillow `Quantize.FASTOCTREE`) existe, pero Pillow usa `MEDIANCUT` por defecto en RGB; el parámetro `kmeans` refina.
- **OKLab** (Ottosson, dominio público/MIT): dos matrices 3×3 + raíz cúbica; corrige la mala predicción de tono de CIELAB en azules. JND en CIE76 ≈ ΔE 2.3.
- **Piel**: regla clásica YCbCr de Chai & Ngan (77≤Cb≤127, 133≤Cr≤173; sesgada a piel clara). Mejor: la clase `body-skin`/`face-skin` de MediaPipe multiclass.
- **Recomendación determinista**: reducir a ≤256 px de lado, histograma OKLab con pesos w = peso_centro × (1−piel) × área; inicializar k=6 desde las cajas MMCQ (orden-invariante), Lloyd ponderado ≤20 iteraciones en float64, fusionar clusters con ΔE2000 < ~5, descartar clusters con área < 5 %, recortar a 3–5. Sin RNG en el motor.

### 2. Segmentación on-device

- **MediaPipe Image Segmenter, `selfie_multiclass_256x256.tflite`**: 16 371 837 bytes, float32, clases `0 background, 1 hair, 2 body-skin, 3 face-skin, 4 clothes, 5 others`; licencia **Apache 2.0** (model card, mayo 2023); IoU medio 77.23 (modelo 256). Pixel 6: 217.76 ms CPU / 71.24 ms GPU. iOS: CocoaPods `MediaPipeTasksVision` (solo CocoaPods, iOS 12+, arm64), API Swift `ImageSegmenter`, `ImageSegmenterOptions.shouldOutputCategoryMask`. No requiere entitlements de pago → compatible con firma personal gratuita.
- **Apple Vision**: `VNGeneratePersonSegmentationRequest` (iOS 15+, `qualityLevel` fast/balanced/accurate) genera "a matte image for a person": persona vs fondo, sin separar ropa/piel. `VNGeneratePersonInstanceMaskRequest` y `VNGenerateForegroundInstanceMaskRequest` (iOS 17+) tampoco. `CIKMeans` (Core Image, iOS 13 según enumeración de terceros) hace k-means con `count`, `passes`, `perceptual`, `inputMeans`, pero su determinismo no está documentado → no usarlo como motor testeable.
- **ML Kit**: subject segmentation es Android-only y beta; selfie segmentation es iOS+Android, beta, solo persona/fondo.
- **MVP**: peso al centro + máscara de persona de Vision (gratis, nativa) opcional. **Después**: MediaPipe multiclass para pesar `clothes` y anular `skin`/`hair`; medir mejora en el set dorado antes de embarcar 16 MB.

### 3. Oráculos y datasets

- **SAM** (Apache 2.0): ViT-H 2.56 GB, ViT-B 375 MB. **SAM 2.1** (Apache 2.0): tiny 156 MB, large 898 MB; `python>=3.10`, `torch>=2.5.1`.
- **SCHP** (MIT): LIP 20 clases (Upper-clothes, Dress, Coat, Pants, Jumpsuits, Skirt, Scarf, Hat, Face, brazos, piernas, zapatos…, mIoU 59.36 %); ATR 18 clases (mIoU 82.29 %). El dataset LIP es "non-commercial… academic research… personal experimentation": válido como oráculo offline, no en producto.
- **Datasets**: Fashionpedia 48 825 imágenes (Flickr, Unsplash, Pexels…), 46 categorías, 294 atributos en 9 supercategorías (Length, Nickname, Opening Type, Silhouettes, Textile finish, Textile Pattern, Non-Textile Type, Neckline, Waistline); DeepFashion2 491K, 13 categorías, solo investigación no comercial vía formulario; CCP 2 098 fotos (1 004 pixel-level, 59 etiquetas, repo Apache-2.0); ModaNet 55 176 imágenes, 13 categorías, CC BY-NC 4.0. **Ninguno anota el color de la prenda**: sirven para máscaras, no para verdad de color. El color de referencia debe salir de máscara + estadístico propio o del set dorado.

### 4. Balance de blancos

En Gehler-Shi (Tabla 1, arXiv 2002.12896): Gray-World 6.36° media / 6.28° mediana; White-Patch 7.55° / 5.86°; FFCC 1.61° / 0.86°. No encontré evidencia específica para ropa. El iPhone ya aplica AWB en el ISP; un segundo gray-world sobre una foto dominada por una prenda de color desatura esa prenda (fallo conocido, no verificado aquí). **No en el MVP por defecto**: implementarlo como flag del harness y reportar recall@1 con/sin.

### 5. Generador sintético (Python ≥ 3.11)

numpy + Pillow (JPEG `quality` 0–95, default 75, `subsampling` 4:2:0/4:2:2/4:4:4) + `perlin-numpy` (MIT, `generate_fractal_noise_2d(shape, res, octaves, persistence, lacunarity)`, shape múltiplo de res) u `opensimplex` 0.4.5.1 (MIT, `noise2array`). Iluminante: Bradford M_A = [0.8951 0.2664 −0.1614; −0.7502 1.7135 0.0367; 0.0389 −0.0685 1.0296] o `colour.adaptation.chromatic_adaptation_VonKries(XYZ, XYZ_w, XYZ_wr, transform='Bradford')`. Oráculo capa 1: `skimage.color.rgb2lab`, `deltaE_ciede2000`. **Ojo**: scikit-learn 1.9.1, scikit-image 0.26.0 y colour-science 0.4.7 exigen Python ≥ 3.11; el 3.9.6 del sistema no sirve → venv con Homebrew `python@3.12` o `uv`.

### 6. Métricas y set dorado

`sklearn.metrics.top_k_accuracy_score(y_true, y_score, k)` para recall@1/@3; entropía y cuota de clase máxima sobre 348 clases con numpy. Acuerdo: `cohen_kappa_score` (2 jueces), `statsmodels.stats.inter_rater.fleiss_kappa(aggregate_raters(...))` (3 jueces); escala Landis-Koch 0.61–0.80 "substantial" (sin base empírica). Herramienta: Label Studio (Apache 2.0, multiusuario) o un HTML estático con top-10 del motor + "ninguna"; consenso por mayoría, desempate por cuarto juez.

## Findings (claim · confidence · URL)

1. MediaPipe SelfieMulticlass: clases 0 background/1 hair/2 body-skin/3 face-skin/4 clothes/5 others, 256×256 float32; Pixel 6 CPU 217.76 ms, GPU 71.24 ms · verified · https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter
2. selfie_multiclass_256x256.tflite = 16 371 837 bytes; selfie_segmenter.tflite = 249 537; deeplab_v3.tflite = 2 780 176 (HEAD content-length) · verified · https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite
3. Model card multiclass: "LICENSED UNDER Apache License, Version 2.0"; ViT; IoU medio 77.23 (256) / 81.10 (512); fecha 2023-05-10 · verified · https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf
4. MediaPipe iOS: pod `MediaPipeTasksVision`, `ImageSegmenter`, `shouldOutputCategoryMask`, modos image/video/liveStream · verified · https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter/ios
5. MediaPipe iOS setup: iOS 12.0+, "can only be installed using CocoaPods", arm64 only · verified · https://developers.google.com/edge/mediapipe/solutions/setup_ios
6. VNGeneratePersonSegmentationRequest: iOS 15+, "matte image for a person", qualityLevel accurate/balanced/fast, VNPixelBufferObservation · verified · https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
7. VNGeneratePersonInstanceMaskRequest y VNGenerateForegroundInstanceMaskRequest: iOS 17+ · verified · https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
8. CIKMeans: propiedades count, inputMeans, passes, perceptual; "Create a palette of the most common colors"; nuevo en iOS 13 · likely (existencia verificada en JSON de Apple; versión vía gist) · https://gist.github.com/JoshuaSullivan/b0e39f9009e44063b366cdc46773601e
9. ML Kit subject segmentation: Android-only, beta, ~200 ms Pixel 7 Pro; selfie segmentation: Android+iOS, beta, persona/fondo · verified · https://developers.google.com/ml-kit/vision/subject-segmentation
10. SAM: Apache 2.0; ViT-H 2 564 550 879 bytes, ViT-B 375 042 383 bytes · verified · https://github.com/facebookresearch/segment-anything
11. SAM 2: Apache 2.0; python>=3.10, torch>=2.5.1; sam2.1_hiera_large.pt 898 083 611 bytes, tiny 156 008 466 · verified · https://github.com/facebookresearch/sam2
12. SCHP: MIT; LIP 20 clases, ATR 18, PPP 7; mIoU LIP 59.36 %, ATR 82.29 % · verified · https://github.com/GoGoDuck912/Self-Correction-Human-Parsing
13. LIP: "freely available to academic and non-commercial entities for non-commercial purposes" · verified · https://www.sysu-hcp.net/resources/datasets/index.html
14. Fashionpedia: 48 825 imágenes de Flickr/Unsplash/Burst/Freestocks/Kaboompics/Pexels; 9 supercategorías de atributos, ninguna de color · verified · https://arxiv.org/abs/2004.12276
15. DeepFashion2: 491K imágenes, 13 categorías, password por Google Form; sin color · verified · https://github.com/switchablenorms/DeepFashion2
16. DeepFashion2 "available only for non-commercial research purpose" (texto del formulario citado por un usuario, sin respuesta del mantenedor) · likely · https://github.com/switchablenorms/DeepFashion2/issues/3
17. Clothing Co-Parsing: 2 098 fotos, 1 004 pixel-level, 59 etiquetas, repo Apache-2.0, sin color · verified · https://github.com/bearpaw/clothing-co-parsing
18. ModaNet: anotaciones CC BY-NC 4.0, 13 categorías, imágenes PaperDoll vía Git LFS; 55 176 imágenes (paper) · verified · https://github.com/eBay/modanet ; https://arxiv.org/abs/1807.01394
19. MMCQ Leptonica: Heckbert 1982, 0.85 por población luego población×volumen, 5/6 sigbits, corte en eje más largo a mitad del lado mayor, sin aleatoriedad · verified · https://raw.githubusercontent.com/DanBloomberg/leptonica/master/src/colorquant2.c
20. color-thief: MIT, v3 cuantiza en OKLCH, quality 1 = todos los píxeles, 10 = uno de cada 10 · verified · https://lokeshdhakar.com/projects/color-thief/
21. k-means++: primer centro uniforme al azar, siguientes ∝ D(x)²; O(log k) en expectativa · verified · https://en.wikipedia.org/wiki/K-means%2B%2B
22. sklearn KMeans: init='k-means++' (greedy), n_init='auto' → 1, random_state int determinista, fit(sample_weight=) · verified · https://scikit-learn.org/stable/modules/generated/sklearn.cluster.KMeans.html
23. Pillow quantize: MEDIANCUT default, MAXCOVERAGE, FASTOCTREE, LIBIMAGEQUANT, kmeans param · verified · https://pillow.readthedocs.io/en/stable/reference/Image.html
24. Pillow JPEG: quality 0–95, default 75, ">95 should be avoided", subsampling 4:4:4/4:2:2/4:2:0 · verified · https://pillow.readthedocs.io/en/stable/handbook/image-file-formats.html
25. OKLab: matrices M1/M2, raíz cúbica, dominio público/MIT, mejor tono que CIELAB · verified · https://bottosson.github.io/posts/oklab/
26. ΔE*ab ≈ 2.3 = JND · verified · https://en.wikipedia.org/wiki/Color_difference
27. Bradford M_A = [0.8951 0.2664 −0.1614; −0.7502 1.7135 0.0367; 0.0389 −0.0685 1.0296], "considered by most experts to be the best" · verified · http://www.brucelindbloom.com/Eqn_ChromAdapt.html
28. colour.adaptation.chromatic_adaptation_VonKries(XYZ, XYZ_w, XYZ_wr, transform='CAT02'), acepta 'Bradford' · verified · https://colour.readthedocs.io/en/latest/generated/colour.adaptation.chromatic_adaptation_VonKries.html
29. colour-science 0.4.7 BSD-3, Python >=3.11 <3.15; scikit-learn 1.9.1 Python >=3.11; scikit-image 0.26.0 Python >=3.11 · verified · https://pypi.org/project/colour-science/
30. Gehler-Shi (Tabla 1): Gray-world 6.36°/6.28°, White-Patch 7.55°/5.86°, FFCC 1.61°/0.86°; NUS: White-patch 9.91/7.44, Gray-world 4.59/3.46 · verified · https://arxiv.org/abs/2002.12896
31. Chai & Ngan YCbCr: 77≤Cb≤127, 133≤Cr≤173, sesgo a piel clara · likely · https://www.sciencedirect.com/science/article/pii/S1877050915018918
32. sklearn top_k_accuracy_score, cohen_kappa_score (κ=(po−pe)/(1−pe), −1..1, weights linear/quadratic) · verified · https://scikit-learn.org/stable/modules/generated/sklearn.metrics.cohen_kappa_score.html
33. statsmodels fleiss_kappa(table, method='fleiss'|'randolph') + aggregate_raters · verified · https://www.statsmodels.org/stable/generated/statsmodels.stats.inter_rater.fleiss_kappa.html
34. Landis-Koch 0.61–0.80 substantial; "supplied no evidence" · verified · https://en.wikipedia.org/wiki/Cohen%27s_kappa
35. Label Studio Apache 2.0, pip install label-studio, multiusuario · verified · https://github.com/HumanSignal/label-studio
36. perlin-numpy MIT, numpy-only, generate_fractal_noise_2d; opensimplex 0.4.5.1 MIT numpy; noise 1.2.2 (2015) C ext · verified · https://github.com/pvigier/perlin-numpy
37. skimage.color.rgb2lab(rgb, illuminant='D65', observer='2'), deltaE_ciede2000(lab1, lab2, kL=1,kC=1,kH=1) · verified · https://scikit-image.org/docs/stable/api/skimage.color.html
