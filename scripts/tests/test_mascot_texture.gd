extends Node

const NEW_MASCOT_PATH: String = "res://Mascot/Gemini_Generated_Image_mjph2dmjph2dmjph(1)(1).png"
const OLD_MASCOT_PATH: String = "res://Mascot/bobr the speculator.png"


func test_all_mascot_presentations_use_the_replacement_image() -> void:
	assert(ResourceLoader.exists(NEW_MASCOT_PATH), "Replacement mascot image is missing.")
	assert(not ResourceLoader.exists(OLD_MASCOT_PATH), "Old mascot image should no longer be in the project.")
	var new_texture: Texture2D = load(NEW_MASCOT_PATH) as Texture2D
	assert(new_texture != null, "Replacement mascot texture did not load.")

	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the game scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame

	var dialogue_mascot: TextureRect = game.get_node(
			"UI/BobrDialogue/MarginContainer/HBoxContainer/Mascot") as TextureRect
	assert(dialogue_mascot.texture == new_texture, "Dialogue should use the replacement mascot.")

	var credits: CreditsPanel = game.get_node("UI/CreditsPanel") as CreditsPanel
	assert(credits != null, "Credits panel was not created.")
	var credits_mascot: TextureRect = credits.get_node("Margin/ContentRow/MascotFrame/Mascot") as TextureRect
	assert(credits_mascot.texture == new_texture, "Credits should use the replacement mascot.")

	var game_over_mascot: TextureRect = game.get_node("UI/GameOverPanel/CenterBox/MascotFrame/Mascot") as TextureRect
	assert(game_over_mascot.texture == new_texture, "Game Over should use the replacement mascot.")
	game.queue_free()
