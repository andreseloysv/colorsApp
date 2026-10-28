"""C de cristal limpia y procedural (octogonal, biseles nítidos, marco hundido), render Cycles para el icono.
usage: blender -b --python cgen.py -- <out.png> <samples> <res>"""
import bpy, bmesh, sys, math, os
a = sys.argv[sys.argv.index("--") + 1:]
OUT, SAMPLES, RES = a[0], int(a[1]), int(a[2])
E = lambda k, d: float(os.environ.get(k, d))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
# Perfil de la C en el plano XZ (x derecha, z arriba).
P = [(0.80, 0.62), (0.47, 0.95), (-0.47, 0.95), (-0.80, 0.62), (-0.80, -0.62), (-0.47, -0.95), (0.47, -0.95),
     (0.80, -0.62), (0.80, -0.40), (-0.16, -0.40), (-0.34, -0.22), (-0.34, 0.22), (-0.16, 0.40), (0.80, 0.40)]
D = E("DEPTH", "0.42")
bm = bmesh.new()
vs = [bm.verts.new((x, -D / 2, z)) for x, z in P]
f = bm.faces.new(vs)
bmesh.ops.recalc_face_normals(bm, faces=[f])
if f.normal.y > 0: f.normal_flip()
ext = bmesh.ops.extrude_face_region(bm, geom=[f])
for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]: v.co.y += D
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
# Marco hundido en la cara frontal y la trasera (como en la referencia).
caps = [fc for fc in bm.faces if abs(fc.normal.y) > 0.99]
bmesh.ops.inset_individual(bm, faces=caps, thickness=E("INSET", "0.075"), depth=-E("RECESS", "0.035"))
me = bpy.data.meshes.new("C"); bm.to_mesh(me); bm.free()
ob = bpy.data.objects.new("C", me); sc.collection.objects.link(ob)
bv = ob.modifiers.new("Bevel", 'BEVEL'); bv.width = E("BEVEL", "0.035"); bv.segments = 2; bv.limit_method = 'ANGLE'
bv.angle_limit = math.radians(30); bv.harden_normals = False
for p in me.polygons: p.use_smooth = False

# Cristal: tres lóbulos con IOR distinto (dispersión simulada, sutil) + película fina muy leve.
m = bpy.data.materials.new("Crystal"); m.use_nodes = True; nt = m.node_tree; nt.nodes.remove(nt.nodes["Principled BSDF"])
prev = None; SPREAD = E("DISP", "0.03")
for k, col in enumerate(((1, 0, 0, 1), (0, 1, 0, 1), (0, 0, 1, 1))):
    g = nt.nodes.new("ShaderNodeBsdfGlass"); g.inputs["Color"].default_value = col
    g.inputs["Roughness"].default_value = 0.0; g.inputs["IOR"].default_value = 1.52 + SPREAD * (k - 1)
    g.inputs["Thin Film Thickness"].default_value = E("FILM", "0")
    if prev is None: prev = g.outputs[0]
    else:
        ad = nt.nodes.new("ShaderNodeAddShader"); nt.links.new(prev, ad.inputs[0]); nt.links.new(g.outputs[0], ad.inputs[1]); prev = ad.outputs[0]
nt.links.new(prev, nt.nodes["Material Output"].inputs["Surface"]); me.materials.append(m)

# Estudio oscuro.
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (E("WORLD", "0.012"),) * 3 + (1,)
def emitter(name, loc, rot, size, strength, color=(1, 1, 1)):
    mt = bpy.data.materials.new(name); mt.use_nodes = True; n = mt.node_tree.nodes; n.remove(n["Principled BSDF"])
    e = n.new("ShaderNodeEmission"); e.inputs["Strength"].default_value = strength; e.inputs["Color"].default_value = color + (1,)
    mt.node_tree.links.new(e.outputs[0], n["Material Output"].inputs[0])
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc); o = bpy.context.active_object
    o.scale = (size[0], size[1], 1); o.rotation_euler = [math.radians(r) for r in rot]; o.data.materials.append(mt)
    o.visible_camera = False; o.visible_shadow = False
    return o
S = E("STRIPS", "25")
# Tiras finas alrededor: dibujan los biseles.
emitter("TopStrip", (0, -0.6, 3.2), (0, 0, 0), (2.6, 0.12, 1), S)
emitter("LeftStrip", (-3.0, -1.2, 0.3), (0, 90, 20), (2.4, 0.10, 1), S)
emitter("RightStrip", (3.0, -0.6, 0.6), (0, -90, -25), (2.4, 0.08, 1), S * 0.8)
emitter("BackRim", (0, 2.5, 1.6), (-60, 0, 0), (3.0, 0.10, 1), S * 1.2)
emitter("LowFill", (0, -3.0, -1.2), (70, 0, 0), (3.0, 0.15, 1), S * 0.25)
emitter("KeySoft", (-2.0, -3.0, 2.6), (55, 0, -35), (1.4, 0.6, 1), E("KEY", "3"))
# Brillo dorado dentro/detrás de la C (el "sol").
emitter("Sun", (-0.35, 0.9, -0.1), (90, 0, 0), (0.6, 0.6, 1), E("SUN", "18"), (1.0, 0.62, 0.28))

# Suelo negro brillante con reflejo.
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.96)); fl = bpy.context.active_object
fm = bpy.data.materials.new("Floor"); fm.use_nodes = True; fp = fm.node_tree.nodes["Principled BSDF"]
fp.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1); fp.inputs["Roughness"].default_value = E("FLOORR", "0.18")
fp.inputs["Specular IOR Level"].default_value = 0.5; fl.data.materials.append(fm)
# Fondo visible: degradado carbón en un plano lejano (solo cámara).
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 8, 0), rotation=(math.radians(90), 0, 0)); bgp = bpy.context.active_object
bm_ = bpy.data.materials.new("Back"); bm_.use_nodes = True; bn = bm_.node_tree.nodes; bn.remove(bn["Principled BSDF"])
be = bn.new("ShaderNodeEmission"); tco = bn.new("ShaderNodeTexCoord"); sep = bn.new("ShaderNodeSeparateXYZ"); rp = bn.new("ShaderNodeValToRGB")
rp.color_ramp.elements[0].position = 0.45; rp.color_ramp.elements[0].color = (0.004, 0.004, 0.005, 1)
rp.color_ramp.elements[1].position = 0.62; rp.color_ramp.elements[1].color = (0.03, 0.03, 0.035, 1)
bl = bm_.node_tree.links; bl.new(tco.outputs["Generated"], sep.inputs[0]); bl.new(sep.outputs["Y"], rp.inputs["Fac"])
bl.new(rp.outputs["Color"], be.inputs["Color"]); bl.new(be.outputs[0], bn["Material Output"].inputs[0])
bgp.data.materials.append(bm_); bgp.visible_glossy = False; bgp.visible_transmission = False; bgp.visible_diffuse = False

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 85; PITCH = E("PITCH", "6"); YAW = E("YAW", "-10"); d = 7.4
ob.rotation_euler[2] = math.radians(YAW)
cam.location = (0, -d * math.cos(math.radians(PITCH)), d * math.sin(math.radians(PITCH)) + 0.05)
cam.rotation_euler = (math.radians(90 - PITCH), 0, 0)
sc.render.engine = 'CYCLES'
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = 'METAL'; prefs.get_devices()
for dv in prefs.devices: dv.use = True
sc.cycles.device = 'GPU'; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.cycles.max_bounces = 48; sc.cycles.transmission_bounces = 48; sc.cycles.glossy_bounces = 24
sc.cycles.caustics_refractive = True; sc.cycles.caustics_reflective = True; sc.cycles.blur_glossy = 0.0
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
sc.render.resolution_x = sc.render.resolution_y = RES; sc.render.filepath = OUT
bpy.ops.render.render(write_still=True); print("RENDERED", OUT)
