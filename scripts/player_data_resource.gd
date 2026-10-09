class_name PlayerDataResource
extends Resource

## Jugador de prueba editable desde el inspector. Solo sirve para rellenar
## [code]Game.test_players[/code] del arnés lobby_test; no tiene relación con
## [code]Statics.PlayerData[/code].

@export var name: String
@export var role: Statics.Role
