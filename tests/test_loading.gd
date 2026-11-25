extends TestCase
## Loading a territory (2026-11-25): disk-cache keys, the ground mesh arrays the worker
## thread computes, and the per-level build resolutions. No network.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func test_road_cache_keys() -> void:
	var places := [{"name": "Affection Fair", "at": Vector2(10, 20), "r": 30.0}]
	var gates := [Vector2(362, 0)]
	var a := TerritoryRoads.cache_path(ILLINOIS, str(places) + str(gates))
	eq(a, TerritoryRoads.cache_path(ILLINOIS.to_upper().replace("0X", "0x"), str(places) + str(gates)), "same inputs, same file (address case ignored)")
	check(a.begins_with(TerritoryRoads.CACHE_DIR) and a.contains("v%d_" % TerritoryRoads.VERSION), "versioned, under the roads cache")
	var moved := [{"name": "Affection Fair", "at": Vector2(12, 20), "r": 30.0}]
	check(a != TerritoryRoads.cache_path(ILLINOIS, str(moved) + str(gates)), "a moved place: another plan")
	check(a != TerritoryRoads.cache_path(ILLINOIS, str(places) + str([])), "different gates: another plan")
	check(a != TerritoryRoads.cache_path("0x2b78", str(places) + str(gates)), "another territory: another plan")


func test_ground_mesh_arrays() -> void:
	var hf := JuliaHeightfield.compute(DeepField.for_territory(Registry.get_territory(ILLINOIS)), ILLINOIS, 33)
	var fine := DeepFieldTerrain.grid_arrays(hf, 2)
	var coarse := DeepFieldTerrain.grid_arrays(hf, 4)
	eq((fine[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 17 * 17, "step 2 over 33 samples: 17²")
	eq((coarse[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 9 * 9, "step 4: 9²")
	var v: PackedVector3Array = coarse[Mesh.ARRAY_VERTEX]
	eq(v[v.size() - 1].x, JuliaHeightfield.SIZE_M * 0.5, "the coarse ground still reaches the border")
	eq(v[0].y, hf.heights[0], "heights are the heightfield's own (same content at every level)")
	for p in Config.QUALITY_PRESETS:
		var step := int(p["mesh_step"])
		eq(int(JuliaHeightfield.SIZE_M) % step, 0, "724 m divides by the mesh step (%d)" % step)
		if bool(p["shadows"]):  # the shadow proxy (2 × step) is built only where the sun casts shadows
			eq(int(JuliaHeightfield.SIZE_M) % (step * 2), 0, "and by its shadow proxy's (%d)" % (step * 2))


func test_level_resolutions() -> void:
	var steps := []
	for p in Config.QUALITY_PRESETS:
		steps.append(int(p["mesh_step"]))
		check(float(p["scale_min"]) <= float(p["scale"]) and float(p["scale"]) <= float(p["scale_max"]), "nominal scale inside its dynamic range")
		check(float(p["crowd"]) > 0.0 and float(p["particles"]) > 0.0, "every level keeps some visitors and particles")
	eq(steps, [4, 4, 2, 2, 2], "Potato and Low draw a 4 m ground, Medium up 2 m")
	eq(Config.QUALITY_PRESETS[3]["msaa"], Viewport.MSAA_2X, "High unchanged: MSAA 2×")
	for i in 3:
		eq(Config.QUALITY_PRESETS[i]["msaa"], Viewport.MSAA_DISABLED, "no MSAA below High (%d)" % i)
