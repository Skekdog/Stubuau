# Stubuau

Generates type stub files from an input module.

Supports:
- Function returns
- Table returns
- Type-asserted returns
- __call metamethod

## Note

Stubuau was originally created for personal use and is likely rough around the edges. It may not be ideal for general use. PRs are welcome.

As part of this, there is a heavy reliance on manual type annotations.

## Example

Given this as input:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _PlaySound = require(ReplicatedStorage.Shared.RoundRule.Common.PlaySound)

export type SoundId = number | Sound | string

export type SoundProperties = {
	Volume: number?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
	SoundGroup: SoundGroup?,
	PlaybackRegion: NumberRange?,
	TimePosition: number?,
	Looped: boolean?,
}

local PlaySound = {}

function PlaySound.PlaySound(sound: SoundId | {SoundId}, position: Vector3?, parent: Instance?, props: SoundProperties?, to: Player?): Sound?
	return _PlaySound.PlaySound(sound, position, parent, props, to)
end

function PlaySound.MakeSound(sound: SoundId | {SoundId}, props: SoundProperties?): Sound
	return _PlaySound.MakeSound(sound, props)
end

setmetatable(PlaySound, {
	__call = function(self, sound: SoundId | {SoundId}, position: Vector3?, parent: Instance?, props: SoundProperties?, to: Player?): Sound?
		return PlaySound.PlaySound(sound, position, parent, props, to)
	end
})

return PlaySound
```

Stubuau will output:

```lua
-- The start of the output can be configured as needed using the `base` parameter.

export type SoundId = number | Sound | string
export type SoundProperties = {
	Volume: number?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
	SoundGroup: SoundGroup?,
	PlaybackRegion: NumberRange?,
	TimePosition: number?,
	Looped: boolean?,
}
return (nil :: any) :: typeof(setmetatable({} :: {
	PlaySound: (sound: SoundId | {SoundId}, position: Vector3?, parent: Instance?, props: SoundProperties?, to: Player?) -> (Sound?),
	MakeSound: (sound: SoundId | {SoundId}, props: SoundProperties?) -> (Sound),
}, {} :: {__call: (self: any, sound: SoundId | {SoundId}, position: Vector3?, parent: Instance?, props: SoundProperties?, to: Player?) -> (Sound?)}))
```

## Usage

This is an example usage using Lune. Stubuau does not require a specific runtime.

```lua
local fs = require("@lune/fs")

local Stubuau = require("Stubuau")

-- The base is added to the start of generated stubs.
local BASE = [[
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.API.Types)
]]

-- This name is passed to Stubuau for logging purposes in case a file could not be processed correctly.
local FILE = "script.luau"

-- This is the actual text content of the file.
local scriptContent = fs.readFile(FILE)

Stubuau.GenerateStub(BASE, scriptContent, FILE)
```

## Installation

You can add Stubuau as a submodule or copy the files manually. Be sure to also include the `poke` submodule.