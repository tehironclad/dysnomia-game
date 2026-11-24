class_name PromptFade
extends RefCounted
## Use-prompts that ease in and out instead of blinking. A prompt fades in
## (FADE_IN); cleared, it lingers a moment (LINGER: a step back over a zone's
## edge doesn't blink it) and then fades out with its last words. A new text
## replaces the old at once.

const FADE_IN := 0.14
const LINGER := 0.12
const FADE_OUT := 0.2


static func set_text(label: Label, text: String) -> void:
	if label == null or not label.is_inside_tree():
		if label:
			label.text = text
		return
	var tw: Tween = label.get_meta("prompt_fade") if label.has_meta("prompt_fade") else null
	var running := tw != null and tw.is_valid() and tw.is_running()
	var fading_out: bool = running and label.get_meta("prompt_fade_out", false)
	# Called every frame with the same text: leave a fade in (or a shown prompt) be.
	if text == "" and (label.text == "" or fading_out):
		return
	if text != "" and text == label.text and not fading_out and (running or label.modulate.a >= 0.999):
		return
	if running:
		tw.kill()
	label.set_meta("prompt_fade_out", text == "")
	if text == "":
		tw = label.create_tween()
		tw.tween_interval(LINGER)
		tw.tween_property(label, "modulate:a", 0.0, FADE_OUT)
		tw.tween_callback(func() -> void: label.text = "")
	else:
		if label.text == "":
			label.modulate.a = 0.0
		label.text = text
		if label.modulate.a >= 0.999:
			return
		tw = label.create_tween()
		tw.tween_property(label, "modulate:a", 1.0, FADE_IN * (1.0 - label.modulate.a))
	label.set_meta("prompt_fade", tw)
