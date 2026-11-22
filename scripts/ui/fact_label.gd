class_name FactLabel
extends Label
## A Label that shows a Fact: "—" when unavailable, "≥" for floors, and the
## source + block as its tooltip. Use set_fact(); never set .text with a
## chain value directly.

var fact: Fact = null
var formatter: Callable = Callable()


func set_fact(f: Fact, fmt: Callable = Callable()) -> void:
	fact = f
	if fmt.is_valid():
		formatter = fmt
	text = f.display(formatter)
	tooltip_text = f.provenance()
	mouse_filter = Control.MOUSE_FILTER_PASS
