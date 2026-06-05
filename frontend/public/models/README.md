# Welcome 3D model

Place the Blender-exported model here:

```text
architect-building.glb
```

Generate it with:

```powershell
blender --background --python scripts/create_blender_welcome_model.py
```

The React welcome scene loads `/models/architect-building.glb` when present and falls back to a procedural Three.js model otherwise.
