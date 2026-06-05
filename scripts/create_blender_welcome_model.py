"""Generate the ARCHITECT welcome GLB with Blender.

Run with Blender installed:
  blender --background --python scripts/create_blender_welcome_model.py

Output:
  frontend/public/models/architect-building.glb
"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "frontend" / "public" / "models" / "architect-building.glb"


def mat(name: str, color: tuple[float, float, float, float], metallic=0.0, roughness=0.4, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1:
        material.blend_method = "BLEND"
        material.use_screen_refraction = True
        material.show_transparent_back = True
    return material


def cube(name: str, loc: tuple[float, float, float], scale: tuple[float, float, float], material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def cylinder(name: str, loc: tuple[float, float, float], radius: float, depth: float, material):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def curve_line(name: str, points: list[tuple[float, float, float]], material, bevel=0.018):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel
    curve.bevel_resolution = 4
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def main() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    concrete = mat("warm_concrete", (0.83, 0.84, 0.83, 1), roughness=0.62)
    slab = mat("polished_slab", (0.95, 0.96, 0.95, 1), roughness=0.38)
    steel = mat("brushed_steel", (0.34, 0.39, 0.43, 1), metallic=0.75, roughness=0.22)
    dark = mat("dark_structural_steel", (0.09, 0.12, 0.15, 1), metallic=0.82, roughness=0.18)
    glass = mat("soft_blue_glass", (0.62, 0.86, 1.0, 0.28), roughness=0.03, alpha=0.28)
    blue = mat("ai_blue_trace", (0.02, 0.58, 1.0, 1), roughness=0.2)
    amber = mat("review_amber_trace", (1.0, 0.55, 0.12, 1), roughness=0.2)

    cube("foundation", (0, -0.1, 0), (8.8, 0.18, 5.8), concrete)
    for y in (0, 1.55, 3.08):
        cube(f"slab_{y}", (0, y, 0), (8.5, 0.16, 5.35), slab)

    for x in (-3.85, 0, 3.85):
        for z in (-2.35, 2.35):
            cylinder(f"column_{x}_{z}", (x, 1.67, z), 0.085, 3.35, steel)

    for y in (1.71, 3.24):
        cube(f"beam_front_{y}", (0, y, -2.35), (8.1, 0.12, 0.14), dark)
        cube(f"beam_back_{y}", (0, y, 2.35), (8.1, 0.12, 0.14), dark)
        for x in (-3.85, 0, 3.85):
            cube(f"beam_cross_{x}_{y}", (x, y, 0), (0.14, 0.12, 5.0), dark)

    for x in (-2.9, -1.45, 0, 1.45, 2.9):
        cube(f"front_glass_low_{x}", (x, 0.78, -2.49), (1.25, 1.2, 0.035), glass)
        cube(f"front_glass_high_{x}", (x, 2.32, -2.49), (1.25, 1.2, 0.035), glass)
    for x in (-1.9, 0, 1.9):
        cube(f"back_glass_low_{x}", (x, 0.78, 2.49), (1.55, 1.2, 0.035), glass)
        cube(f"back_glass_high_{x}", (x, 2.32, 2.49), (1.55, 1.2, 0.035), glass)

    core = cube("service_core", (1.55, 1.42, 0.55), (0.78, 2.75, 1.0), concrete)
    core.location += Vector((0, 0, 0))

    curve_line(
        "blue_coordination_path",
        [(-3.85, 1.72, -2.35), (0, 1.72, -2.35), (0, 1.72, 2.35), (3.85, 1.72, 2.35)],
        blue,
    )
    curve_line("blue_roof_axis", [(-3.85, 3.24, -2.35), (3.85, 3.24, -2.35)], blue)
    curve_line("amber_vertical_review", [(3.85, 0.12, -2.35), (3.85, 3.35, -2.35)], amber)
    curve_line("amber_lateral_review", [(3.85, 1.68, -2.35), (3.85, 1.68, 2.35)], amber)

    bpy.ops.object.light_add(type="AREA", location=(0, 7, 4))
    bpy.context.object.name = "large_softbox"
    bpy.context.object.data.energy = 420
    bpy.context.object.data.size = 7

    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT),
        export_format="GLB",
        export_materials="EXPORT",
        export_apply=True,
    )


if __name__ == "__main__":
    main()
