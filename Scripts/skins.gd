extends Node
## Loads all skin materials from res://skins/ (*.tres files).

var _materials: Array[Material] = []
var _names: Array[String] = []

func _ready() -> void:
	refresh()

func refresh() -> void:
	_materials.clear()
	_names.clear()
	var dir := DirAccess.open("res://skins")
	if dir == null:
		return
	for file in dir.get_files():
		# 1. Catch files that were converted during export (.tres.remap)
		if file.ends_with(".tres.remap"):
			file = file.trim_suffix(".remap") # Correctly strips '.remap' leaving '.tres'
			
		# 2. Check for standard .tres (works both in-editor and after stripping)
		if file.ends_with(".tres"):
			var mat := load("res://skins/" + file) as Material
			if mat:
				_materials.append(mat)
				_names.append(file.get_basename())



func count() -> int:
	return _materials.size()

func material_at(index: int) -> Material:
	if index < 0 or index >= _materials.size():
		return null
	return _materials[index]

func skin_name(index: int) -> String:
	if index < 0 or index >= _names.size():
		return "?"
	return _names[index].capitalize()
