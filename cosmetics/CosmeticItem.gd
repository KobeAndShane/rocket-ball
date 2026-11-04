class_name CosmeticItem
extends Resource
## Data-only cosmetic definition. Every field affects presentation only; the
## car collider comes from CarTuning and never from a cosmetic resource.

@export var id: String = ""
@export var display_name: String = "Cosmetic"
@export var description: String = ""
## body, wheel, boost, trail, decal, explosion or antenna.
@export var slot: String = "body"
## common, uncommon, rare, epic or legendary.
@export var rarity: String = "common"
@export var price: int = 0
@export var unlock_level: int = 1
@export var default_owned: bool = false
@export var season_only: bool = false

@export_group("Materials")
@export var primary_color: Color = Color(0.3, 0.65, 1.0)
@export var secondary_color: Color = Color(0.15, 0.2, 0.28)
@export var accent_color: Color = Color(0.4, 0.95, 1.0)
@export var metallic: float = 0.45
@export var roughness: float = 0.35
@export var emission_strength: float = 0.25

@export_group("Body")
## Visual scale applied to BodyMesh/CabinMesh. The physics collider is fixed.
@export var body_scale: Vector3 = Vector3.ONE
@export var body_offset: Vector3 = Vector3.ZERO
@export var cabin_scale: Vector3 = Vector3.ONE
@export var cabin_offset: Vector3 = Vector3.ZERO

@export_group("Wheels")
@export var wheel_radius: float = 0.34
@export var wheel_width: float = 0.16
@export var wheel_spokes: int = 0

@export_group("Effects")
## 0 none, 1 stripes, 2 hex.
@export var decal_pattern: int = 0
## 0 none, 1 flag.
@export var antenna_style: int = 0
## 0 none, 1 standard, 2 ion, 3 supernova.
@export var trail_style: int = 0
## 0 none, 1 burst, 2 singularity.
@export var explosion_style: int = 0


func rarity_color() -> Color:
	match rarity:
		"uncommon":
			return Color(0.4, 0.95, 0.55)
		"rare":
			return Color(0.35, 0.7, 1.0)
		"epic":
			return Color(0.8, 0.45, 1.0)
		"legendary":
			return Color(1.0, 0.72, 0.25)
		_:
			return Color(0.7, 0.75, 0.8)
