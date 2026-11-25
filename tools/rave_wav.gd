extends SceneTree
## Renders a territory's arcade DJ set (RaveTrack, the full 16-bar cycle) to a WAV you can listen to:
##   godot --headless --path . -s res://tools/rave_wav.gd -- --out=<abs .wav> [--qing=0x…] [--cycles=1]
## Prints the style it was made from (tempo, key, groove). Nothing is read from the chain.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var addr := ""
	var cycles := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--qing="):
			addr = a.substr(7)
		elif a.begins_with("--cycles="):
			cycles = maxi(1, int(a.substr(9)))
	if out == "":
		print("usage: -- --out=<abs .wav> [--qing=0x…] [--cycles=1]")
		quit(1)
		return
	var registry: Node = root.get_node("Registry")
	var territory: Dictionary = registry.get_territory(addr) if addr != "" else (registry.all()[0] if registry.count() > 0 else {})
	var style: Dictionary = load("res://scripts/places/arcade/rave_style.gd").for_territory(territory)
	var track = load("res://scripts/places/arcade/rave_track.gd")
	var sp: Dictionary = track.spec(style)
	print("%s: %d BPM, root +%d semitones over A, groove %d" % [territory.get("name", "(fallback)"), sp["bpm"], sp["root"], sp["groove"]])
	var kit: Dictionary = track.make_kit(sp)
	var bars := {}
	var data := PackedByteArray()
	for c in cycles:
		for b in 16:
			var k: String = track.bar_key(b)
			if not bars.has(k):
				var parts := k.split(":")
				bars[k] = track.render(sp, parts[0], int(parts[1]), kit)
			for v in bars[k]:
				var l := int(clampf(v.x, -1.0, 1.0) * 32767.0)
				var r := int(clampf(v.y, -1.0, 1.0) * 32767.0)
				data.append(l & 0xff)
				data.append((l >> 8) & 0xff)
				data.append(r & 0xff)
				data.append((r >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = track.RATE
	w.data = data
	w.save_to_wav(out)
	print("wrote %s (%.1f s)" % [out, data.size() / 4.0 / track.RATE])
	quit(0)
